// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

contract SvnGenesisRewardPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IERC20 token;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accSvnPerShare;
        bool isStarted;
        uint256 maxDeposit;
    }

    EnumerableSet.AddressSet private _comissionTokens;
    uint256 public comissionPercent;

    address public operator;
    IERC20 public svn;
    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint = 0;
    uint256 public poolStartTime;
    uint256 public poolEndTime;

    uint256 public svnPerSecond;
    uint256 public runningTime;
    uint256 public totalRewards;

    function comissionTokensCount() external view returns (uint256) {
        return _comissionTokens.length();
    }

    function comissionToken(uint256 index) external view returns (address) {
        return _comissionTokens.at(index);
    }

    function pendingSVN(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSvnPerShare = pool.accSvnPerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 _svnReward = _generatedReward.mul(pool.allocPoint).div(
                totalAllocPoint
            );
            accSvnPerShare = accSvnPerShare.add(
                _svnReward.mul(1e18).div(tokenSupply)
            );
        }
        return user.amount.mul(accSvnPerShare).div(1e18).sub(user.rewardDebt);
    }

    function getGeneratedReward(uint256 _fromTime, uint256 _toTime)
        public
        view
        returns (uint256)
    {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime)
                return poolEndTime.sub(poolStartTime).mul(svnPerSecond);
            return poolEndTime.sub(_fromTime).mul(svnPerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime)
                return _toTime.sub(poolStartTime).mul(svnPerSecond);
            return _toTime.sub(_fromTime).mul(svnPerSecond);
        }
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(
                poolInfo[pid].token != _token,
                "SvnGenesisPool: existing pool?"
            );
        }
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _svn,
        address[] memory comissionTokens_,
        uint256 _comissionPercent,
        uint256 _poolStartTime,
        uint256 _totalRewards,
        uint256 _runningTime
    ) public {
        //        require(block.timestamp < _poolStartTime, "late");
        require(_svn != address(0), "SvnGenesisPool: svn is zero address");
        require(_totalRewards > 0, "SvnGenesisPool: totalRewards is zero");
        require(_runningTime > 0, "SvnGenesisPool: runningTime is zero");
        svn = IERC20(_svn);
        totalRewards = _totalRewards;
        runningTime = _runningTime;
        svnPerSecond = totalRewards.div(runningTime);
        for (uint256 i = 0; i < comissionTokens_.length; i++)
            _comissionTokens.add(comissionTokens_[i]);
        comissionPercent = _comissionPercent;
        poolStartTime = _poolStartTime;
        poolEndTime = poolStartTime.add(runningTime);
        operator = msg.sender;
    }

    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime,
        uint256 _maxDeposit
    ) external onlyOperator {
        checkPoolDuplicate(_token);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.timestamp < poolStartTime) {
            if (_lastRewardTime == 0) {
                _lastRewardTime = poolStartTime;
            } else {
                if (_lastRewardTime < poolStartTime) {
                    _lastRewardTime = poolStartTime;
                }
            }
        } else {
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted = (_lastRewardTime <= poolStartTime) ||
            (_lastRewardTime <= block.timestamp);
        poolInfo.push(
            PoolInfo({
                token: _token,
                allocPoint: _allocPoint,
                lastRewardTime: _lastRewardTime,
                accSvnPerShare: 0,
                isStarted: _isStarted,
                maxDeposit: _maxDeposit
            })
        );
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    function deposit(uint256 _pid, uint256 _amount) external {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user
                .amount
                .mul(pool.accSvnPerShare)
                .div(1e18)
                .sub(user.rewardDebt);
            if (_pending > 0) {
                safeSvnTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        uint256 possibleToDeposit = pool.maxDeposit.sub(user.amount);
        uint256 amount = _amount > possibleToDeposit
            ? possibleToDeposit
            : _amount;
        if (amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), amount);
            if (_comissionTokens.contains(address(pool.token))) {
                uint256 hundred = 10000;
                user.amount = user.amount.add(
                    amount.mul(hundred.sub(comissionPercent)).div(hundred)
                );
            } else {
                user.amount = user.amount.add(amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accSvnPerShare).div(1e18);
        emit Deposit(_sender, _pid, amount);
    }

    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.token.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 amount,
        address to
    ) external onlyOperator {
        if (block.timestamp < poolEndTime + 30 days) {
            require(_token != svn, "svn");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "pool.token");
            }
        }
        _token.safeTransfer(to, amount);
    }

    function set(uint256 _pid, uint256 _allocPoint) external onlyOperator {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        pool.allocPoint = _allocPoint;
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function withdraw(uint256 _pid, uint256 _amount) external {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accSvnPerShare).div(1e18).sub(
            user.rewardDebt
        );
        if (_pending > 0) {
            safeSvnTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accSvnPerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (tokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 _svnReward = _generatedReward.mul(pool.allocPoint).div(
                totalAllocPoint
            );
            pool.accSvnPerShare = pool.accSvnPerShare.add(
                _svnReward.mul(1e18).div(tokenSupply)
            );
        }
        pool.lastRewardTime = block.timestamp;
    }

    function safeSvnTransfer(address _to, uint256 _amount) internal {
        uint256 _svnBalance = svn.balanceOf(address(this));
        if (_svnBalance > 0) {
            if (_amount > _svnBalance) {
                svn.safeTransfer(_to, _svnBalance);
            } else {
                svn.safeTransfer(_to, _amount);
            }
        }
    }

    modifier onlyOperator() {
        require(
            operator == msg.sender,
            "SvnGenesisPool: caller is not the operator"
        );
        _;
    }
}
