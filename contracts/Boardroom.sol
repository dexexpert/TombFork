// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./ContractGuard.sol";
import "./IBasisAsset.sol";
import "./ITreasury.sol";

contract ShareWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public share;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        share.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 svnShare = _balances[msg.sender];
        require(
            svnShare >= amount,
            "SvnWheel: withdraw request greater than staked amount"
        );
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = svnShare.sub(amount);
        share.safeTransfer(msg.sender, amount);
    }
}

contract Boardroom is ShareWrapper, ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    struct Wheelseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
    }

    struct WheelSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    address public operator;
    bool public initialized = false;
    IERC20 public svn;
    ITreasury public treasury;
    mapping(address => Wheelseat) public wheels;
    WheelSnapshot[] public wheelHistory;
    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    modifier onlyOperator() {
        require(operator == msg.sender, "SvnWheel: caller is not the operator");
        _;
    }

    modifier wheelExists() {
        require(
            balanceOf(msg.sender) > 0,
            "SvnWheel: The wheel does not exist"
        );
        _;
    }

    modifier updateReward(address wheel) {
        if (wheel != address(0)) {
            Wheelseat memory seat = wheels[wheel];
            seat.rewardEarned = earned(wheel);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            wheels[wheel] = seat;
        }
        _;
    }

    modifier notInitialized() {
        require(!initialized, "SvnWheel: already initialized");
        _;
    }

    function initialize(
        IERC20 _svn,
        IERC20 _share,
        ITreasury _treasury
    ) public notInitialized {
        svn = _svn;
        share = _share;
        treasury = _treasury;
        WheelSnapshot memory genesisSnapshot = WheelSnapshot({
            time: block.number,
            rewardReceived: 0,
            rewardPerShare: 0
        });
        wheelHistory.push(genesisSnapshot);
        withdrawLockupEpochs = 6;
        rewardLockupEpochs = 3;
        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setLockUp(
        uint256 _withdrawLockupEpochs,
        uint256 _rewardLockupEpochs
    ) external onlyOperator {
        require(
            _withdrawLockupEpochs >= _rewardLockupEpochs &&
                _withdrawLockupEpochs <= 56,
            "_withdrawLockupEpochs: out of range"
        );
        withdrawLockupEpochs = _withdrawLockupEpochs;
        rewardLockupEpochs = _rewardLockupEpochs;
    }

    function latestSnapshotIndex() public view returns (uint256) {
        return wheelHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (WheelSnapshot memory) {
        return wheelHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address wheel)
        public
        view
        returns (uint256)
    {
        return wheels[wheel].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address wheel)
        internal
        view
        returns (WheelSnapshot memory)
    {
        return wheelHistory[getLastSnapshotIndexOf(wheel)];
    }

    function canWithdraw(address wheel) external view returns (bool) {
        return
            wheels[wheel].epochTimerStart.add(withdrawLockupEpochs) <=
            treasury.epoch();
    }

    function canClaimReward(address wheel) external view returns (bool) {
        return
            wheels[wheel].epochTimerStart.add(rewardLockupEpochs) <=
            treasury.epoch();
    }

    function epoch() external view returns (uint256) {
        return treasury.epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return treasury.nextEpochPoint();
    }

    function getSvnPrice() external view returns (uint256) {
        return treasury.getSvnPrice();
    }

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address wheel) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(wheel).rewardPerShare;
        return
            balanceOf(wheel).mul(latestRPS.sub(storedRPS)).div(1e18).add(
                wheels[wheel].rewardEarned
            );
    }

    function stake(uint256 amount)
        public
        override
        onlyOneBlock
        updateReward(msg.sender)
    {
        require(amount > 0, "SvnWheel: Cannot stake 0");
        super.stake(amount);
        wheels[msg.sender].epochTimerStart = treasury.epoch();
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        override
        onlyOneBlock
        wheelExists
        updateReward(msg.sender)
    {
        require(amount > 0, "SvnWheel: Cannot withdraw 0");
        require(
            wheels[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <=
                treasury.epoch(),
            "SvnWheel: still in withdraw lockup"
        );
        claimReward();
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = wheels[msg.sender].rewardEarned;
        if (reward > 0) {
            require(
                wheels[msg.sender].epochTimerStart.add(rewardLockupEpochs) <=
                    treasury.epoch(),
                "SvnWheel: still in reward lockup"
            );
            wheels[msg.sender].epochTimerStart = treasury.epoch();
            wheels[msg.sender].rewardEarned = 0;
            svn.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function allocateSeigniorage(uint256 amount)
        external
        onlyOneBlock
        onlyOperator
    {
        require(amount > 0, "SvnWheel: Cannot allocate 0");
        require(
            totalSupply() > 0,
            "SvnWheel: Cannot allocate when totalSupply is 0"
        );
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));
        WheelSnapshot memory newSnapshot = WheelSnapshot({
            time: block.number,
            rewardReceived: amount,
            rewardPerShare: nextRPS
        });
        wheelHistory.push(newSnapshot);
        svn.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        require(address(_token) != address(svn), "svn");
        require(address(_token) != address(share), "share");
        _token.safeTransfer(_to, _amount);
    }
}
