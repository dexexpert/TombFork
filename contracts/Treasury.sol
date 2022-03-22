// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./Operator.sol";
import "./ContractGuard.sol";
import "./IBasisAsset.sol";
import "./IOracle.sol";
import "./IBoardroom.sol";

contract Treasury is ContractGuard {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    uint256 public constant PERIOD = 6 hours;
    address public operator;
    bool public initialized = false;
    uint256 public startTime;
    uint256 public epoch = 0;
    uint256 public epochSupplyContractionLeft = 0;
    address[] public excludedFromTotalSupply;
    address public svn;
    address public svnbond;
    address public svnshare;
    address public svnWheel;
    address public svnOracle;
    uint256 public svnPriceOne;
    uint256 public svnPriceCeiling;
    uint256 public seigniorageSaved;
    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;
    uint256 public maxSupplyExpansionPercent;
    uint256 public bondDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDebtRatioPercent;
    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;
    uint256 public previousEpochSvnPrice;
    uint256 public maxDiscountRate;
    uint256 public maxPremiumRate;
    uint256 public discountPercent;
    uint256 public premiumThreshold;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt;
    address public daoFund;
    uint256 public daoFundSharedPercent;
    address public devFund;
    uint256 public devFundSharedPercent;

    function getBurnableSvnLeft()
        external
        view
        returns (uint256 _burnableSvnLeft)
    {
        uint256 _svnPrice = getSvnPrice();
        if (_svnPrice <= svnPriceOne) {
            uint256 _svnSupply = getSvnCirculatingSupply();
            uint256 _bondMaxSupply = _svnSupply.mul(maxDebtRatioPercent).div(
                10000
            );
            uint256 _bondSupply = IERC20(svnbond).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint256 _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint256 _maxBurnableSvn = _maxMintableBond.mul(_svnPrice).div(
                    1e18
                );
                _burnableSvnLeft = Math.min(
                    epochSupplyContractionLeft,
                    _maxBurnableSvn
                );
            }
        }
    }

    function getSvnUpdatedPrice() external view returns (uint256 _svnPrice) {
        try IOracle(svnOracle).twap(svn, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult SVN price from the oracle");
        }
    }

    function getRedeemableBonds()
        external
        view
        returns (uint256 _redeemableBonds)
    {
        uint256 _svnPrice = getSvnPrice();
        if (_svnPrice > svnPriceCeiling) {
            uint256 _totalSvn = IERC20(svn).balanceOf(address(this));
            uint256 _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalSvn.mul(1e18).div(_rate);
            }
        }
    }

    function getReserve() external view returns (uint256) {
        return seigniorageSaved;
    }

    function isInitialized() external view returns (bool) {
        return initialized;
    }

    function getBondDiscountRate() public view returns (uint256 _rate) {
        uint256 _svnPrice = getSvnPrice();
        if (_svnPrice <= svnPriceOne) {
            if (discountPercent == 0) {
                _rate = svnPriceOne;
            } else {
                uint256 _bondAmount = svnPriceOne.mul(1e18).div(_svnPrice);
                uint256 _discountAmount = _bondAmount
                    .sub(svnPriceOne)
                    .mul(discountPercent)
                    .div(10000);
                _rate = svnPriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint256 _rate) {
        uint256 _svnPrice = getSvnPrice();
        if (_svnPrice > svnPriceCeiling) {
            uint256 _svnPricePremiumThreshold = svnPriceOne
                .mul(premiumThreshold)
                .div(100);
            if (_svnPrice >= _svnPricePremiumThreshold) {
                uint256 _premiumAmount = _svnPrice
                    .sub(svnPriceOne)
                    .mul(premiumPercent)
                    .div(10000);
                _rate = svnPriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                _rate = svnPriceOne;
            }
        }
    }

    function getSvnCirculatingSupply() public view returns (uint256) {
        IERC20 svnErc20 = IERC20(svn);
        uint256 totalSupply = svnErc20.totalSupply();
        uint256 balanceExcluded = 0;
        for (
            uint8 entryId = 0;
            entryId < excludedFromTotalSupply.length;
            ++entryId
        ) {
            balanceExcluded = balanceExcluded.add(
                svnErc20.balanceOf(excludedFromTotalSupply[entryId])
            );
        }
        return totalSupply.sub(balanceExcluded);
    }

    function getSvnPrice() public view returns (uint256 svnPrice) {
        try IOracle(svnOracle).consult(svn, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult SVN price from the oracle");
        }
    }

    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(PERIOD));
    }

    event Initialized(address indexed executor, uint256 at);
    event BurnedBonds(address indexed from, uint256 bondAmount);
    event RedeemedBonds(
        address indexed from,
        uint256 svnAmount,
        uint256 bondAmount,
        uint256 epochNumber
    );
    event BoughtBonds(
        address indexed from,
        uint256 svnAmount,
        uint256 bondAmount,
        uint256 epochNumber
    );
    event TreasuryFunded(
        uint256 timestamp,
        uint256 seigniorage,
        uint256 epochNumber
    );
    event SvnWheelFunded(
        uint256 timestamp,
        uint256 seigniorage,
        uint256 epochNumber
    );
    event DaoFundFunded(
        uint256 timestamp,
        uint256 seigniorage,
        uint256 epochNumber
    );
    event DevFundFunded(
        uint256 timestamp,
        uint256 seigniorage,
        uint256 epochNumber
    );

    function allocateSeigniorage()
        external
        onlyOneBlock
        checkCondition
        checkEpoch
        checkOperator
    {
        _updateSvnPrice();
        previousEpochSvnPrice = getSvnPrice();
        uint256 svnSupply = getSvnCirculatingSupply().sub(seigniorageSaved);
        if (epoch < bootstrapEpochs) {
            _sendToSvnWheel(
                svnSupply.mul(bootstrapSupplyExpansionPercent).div(10000)
            );
        } else {
            if (previousEpochSvnPrice > svnPriceCeiling) {
                uint256 bondSupply = IERC20(svnbond).totalSupply();
                uint256 _percentage = previousEpochSvnPrice.sub(svnPriceOne);
                uint256 _savedForBond;
                uint256 _savedForSvnWheel;
                uint256 _mse = _calculateMaxSupplyExpansionPercent(svnSupply)
                    .mul(1e14);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                if (
                    seigniorageSaved >=
                    bondSupply.mul(bondDepletionFloorPercent).div(10000)
                ) {
                    _savedForSvnWheel = svnSupply.mul(_percentage).div(1e18);
                } else {
                    uint256 _seigniorage = svnSupply.mul(_percentage).div(1e18);
                    _savedForSvnWheel = _seigniorage
                        .mul(seigniorageExpansionFloorPercent)
                        .div(10000);
                    _savedForBond = _seigniorage.sub(_savedForSvnWheel);
                    if (mintingFactorForPayingDebt > 0) {
                        _savedForBond = _savedForBond
                            .mul(mintingFactorForPayingDebt)
                            .div(10000);
                    }
                }
                if (_savedForSvnWheel > 0) {
                    _sendToSvnWheel(_savedForSvnWheel);
                }
                if (_savedForBond > 0) {
                    seigniorageSaved = seigniorageSaved.add(_savedForBond);
                    IBasisAsset(svn).mint(address(this), _savedForBond);
                    emit TreasuryFunded(now, _savedForBond, epoch);
                }
            }
        }
    }

    function buyBonds(uint256 _svnAmount, uint256 targetPrice)
        external
        onlyOneBlock
        checkCondition
        checkOperator
    {
        require(
            _svnAmount > 0,
            "Treasury: cannot purchase bonds with zero amount"
        );
        uint256 svnPrice = getSvnPrice();
        require(svnPrice == targetPrice, "Treasury: SVN price moved");
        require(
            svnPrice < svnPriceOne,
            "Treasury: svnPrice not eligible for bond purchase"
        );
        require(
            _svnAmount <= epochSupplyContractionLeft,
            "Treasury: not enough bond left to purchase"
        );
        uint256 _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: invalid bond rate");
        uint256 _bondAmount = _svnAmount.mul(_rate).div(1e18);
        uint256 svnSupply = getSvnCirculatingSupply();
        uint256 newBondSupply = IERC20(svnbond).totalSupply().add(_bondAmount);
        require(
            newBondSupply <= svnSupply.mul(maxDebtRatioPercent).div(10000),
            "over max debt ratio"
        );
        IBasisAsset(svn).burnFrom(msg.sender, _svnAmount);
        IBasisAsset(svnbond).mint(msg.sender, _bondAmount);
        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_svnAmount);
        _updateSvnPrice();
        emit BoughtBonds(msg.sender, _svnAmount, _bondAmount, epoch);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        require(address(_token) != address(svn), "svn");
        require(address(_token) != address(svnbond), "bond");
        require(address(_token) != address(svnshare), "share");
        _token.safeTransfer(_to, _amount);
    }

    function svnWheelAllocateSeigniorage(uint256 amount) external onlyOperator {
        IBoardroom(svnWheel).allocateSeigniorage(amount);
    }

    function svnWheelGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IBoardroom(svnWheel).governanceRecoverUnsupported(_token, _amount, _to);
    }

    function svnWheelSetLockUp(
        uint256 _withdrawLockupEpochs,
        uint256 _rewardLockupEpochs
    ) external onlyOperator {
        IBoardroom(svnWheel).setLockUp(
            _withdrawLockupEpochs,
            _rewardLockupEpochs
        );
    }

    function svnWheelSetOperator(address _operator) external onlyOperator {
        IBoardroom(svnWheel).setOperator(_operator);
    }

    function initialize(
        address _svn,
        address _svnbond,
        address _svnshare,
        address _svnOracle,
        address _svnWheel,
        uint256 _startTime,
        address[] memory excludedFromTotalSupply_
    ) external notInitialized {
        svn = _svn;
        svnbond = _svnbond;
        svnshare = _svnshare;
        svnOracle = _svnOracle;
        svnWheel = _svnWheel;
        startTime = _startTime;
        svnPriceOne = 10**18;
        svnPriceCeiling = svnPriceOne.mul(101).div(100);
        supplyTiers = [
            0 ether,
            500000 ether,
            1000000 ether,
            1500000 ether,
            2000000 ether,
            5000000 ether,
            10000000 ether,
            20000000 ether,
            50000000 ether
        ];
        maxExpansionTiers = [450, 400, 350, 300, 250, 200, 150, 125, 100];
        maxSupplyExpansionPercent = 400;
        bondDepletionFloorPercent = 10000;
        seigniorageExpansionFloorPercent = 3500;
        maxSupplyContractionPercent = 300;
        maxDebtRatioPercent = 3500;
        premiumThreshold = 110;
        premiumPercent = 7000;
        bootstrapEpochs = 28;
        bootstrapSupplyExpansionPercent = 450;
        seigniorageSaved = IERC20(svn).balanceOf(address(this));
        initialized = true;
        operator = msg.sender;
        for (uint256 i = 0; i < excludedFromTotalSupply_.length; i++) {
            excludedFromTotalSupply.push(excludedFromTotalSupply_[i]);
            // SvnGenesisPool && SvnRewardPool
        }
        emit Initialized(msg.sender, block.number);
    }

    function redeemBonds(uint256 _bondAmount, uint256 targetPrice)
        external
        onlyOneBlock
        checkCondition
        checkOperator
    {
        require(
            _bondAmount > 0,
            "Treasury: cannot redeem bonds with zero amount"
        );
        uint256 svnPrice = getSvnPrice();
        require(svnPrice == targetPrice, "Treasury: SVN price moved");
        require(
            svnPrice > svnPriceCeiling,
            "Treasury: svnPrice not eligible for bond purchase"
        );
        uint256 _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");
        uint256 _svnAmount = _bondAmount.mul(_rate).div(1e18);
        require(
            IERC20(svn).balanceOf(address(this)) >= _svnAmount,
            "Treasury: treasury has no more budget"
        );
        seigniorageSaved = seigniorageSaved.sub(
            Math.min(seigniorageSaved, _svnAmount)
        );
        IBasisAsset(svnbond).burnFrom(msg.sender, _bondAmount);
        IERC20(svn).safeTransfer(msg.sender, _svnAmount);
        _updateSvnPrice();
        emit RedeemedBonds(msg.sender, _svnAmount, _bondAmount, epoch);
    }

    function setBondDepletionFloorPercent(uint256 _bondDepletionFloorPercent)
        external
        onlyOperator
    {
        require(
            _bondDepletionFloorPercent >= 500 &&
                _bondDepletionFloorPercent <= 10000,
            "out of range"
        );
        bondDepletionFloorPercent = _bondDepletionFloorPercent;
    }

    function setBootstrap(
        uint256 _bootstrapEpochs,
        uint256 _bootstrapSupplyExpansionPercent
    ) external onlyOperator {
        require(_bootstrapEpochs <= 120, "_bootstrapEpochs: out of range");
        require(
            _bootstrapSupplyExpansionPercent >= 100 &&
                _bootstrapSupplyExpansionPercent <= 1000,
            "_bootstrapSupplyExpansionPercent: out of range"
        );
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }

    function setDiscountPercent(uint256 _discountPercent)
        external
        onlyOperator
    {
        require(_discountPercent <= 20000, "_discountPercent is over 200%");
        discountPercent = _discountPercent;
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _devFund,
        uint256 _devFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 3000, "out of range");
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 1000, "out of range");
        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        devFund = _devFund;
        devFundSharedPercent = _devFundSharedPercent;
    }

    function setSvnOracle(address _svnOracle) external onlyOperator {
        svnOracle = _svnOracle;
    }

    function setSvnPriceCeiling(uint256 _svnPriceCeiling)
        external
        onlyOperator
    {
        require(
            _svnPriceCeiling >= svnPriceOne &&
                _svnPriceCeiling <= svnPriceOne.mul(120).div(100),
            "out of range"
        );
        svnPriceCeiling = _svnPriceCeiling;
    }

    function setSvnWheel(address _svnWheel) external onlyOperator {
        svnWheel = _svnWheel;
    }

    function setMaxDebtRatioPercent(uint256 _maxDebtRatioPercent)
        external
        onlyOperator
    {
        require(
            _maxDebtRatioPercent >= 1000 && _maxDebtRatioPercent <= 10000,
            "out of range"
        );
        maxDebtRatioPercent = _maxDebtRatioPercent;
    }

    function setMaxDiscountRate(uint256 _maxDiscountRate)
        external
        onlyOperator
    {
        maxDiscountRate = _maxDiscountRate;
    }

    function setMaxExpansionTiersEntry(uint8 _index, uint256 _value)
        external
        onlyOperator
        returns (bool)
    {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        require(_value >= 10 && _value <= 1000, "_value: out of range");
        maxExpansionTiers[_index] = _value;
        return true;
    }

    function setMaxPremiumRate(uint256 _maxPremiumRate) external onlyOperator {
        maxPremiumRate = _maxPremiumRate;
    }

    function setMaxSupplyContractionPercent(
        uint256 _maxSupplyContractionPercent
    ) external onlyOperator {
        require(
            _maxSupplyContractionPercent >= 100 &&
                _maxSupplyContractionPercent <= 1500,
            "out of range"
        );
        maxSupplyContractionPercent = _maxSupplyContractionPercent;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent)
        external
        onlyOperator
    {
        require(
            _maxSupplyExpansionPercent >= 10 &&
                _maxSupplyExpansionPercent <= 1000,
            "_maxSupplyExpansionPercent: out of range"
        );
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt)
        external
        onlyOperator
    {
        require(
            _mintingFactorForPayingDebt >= 10000 &&
                _mintingFactorForPayingDebt <= 20000,
            "_mintingFactorForPayingDebt: out of range"
        );
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setPremiumPercent(uint256 _premiumPercent) external onlyOperator {
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");
        premiumPercent = _premiumPercent;
    }

    function setPremiumThreshold(uint256 _premiumThreshold)
        external
        onlyOperator
    {
        require(
            _premiumThreshold >= svnPriceCeiling,
            "_premiumThreshold exceeds svnPriceCeiling"
        );
        require(
            _premiumThreshold <= 150,
            "_premiumThreshold is higher than 1.5"
        );
        premiumThreshold = _premiumThreshold;
    }

    function setSupplyTiersEntry(uint8 _index, uint256 _value)
        external
        onlyOperator
        returns (bool)
    {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        if (_index > 0) {
            require(_value > supplyTiers[_index - 1]);
        }
        if (_index < 8) {
            require(_value < supplyTiers[_index + 1]);
        }
        supplyTiers[_index] = _value;
        return true;
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _svnSupply)
        internal
        returns (uint256)
    {
        for (uint8 tierId = 8; tierId >= 0; --tierId) {
            if (_svnSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function _sendToSvnWheel(uint256 _amount) internal {
        IBasisAsset(svn).mint(address(this), _amount);
        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(svn).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(now, _daoFundSharedAmount, epoch);
        }
        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20(svn).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(now, _devFundSharedAmount, epoch);
        }
        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount);
        IERC20(svn).safeApprove(svnWheel, 0);
        IERC20(svn).safeApprove(svnWheel, _amount);
        IBoardroom(svnWheel).allocateSeigniorage(_amount);
        emit SvnWheelFunded(now, _amount, epoch);
    }

    function _updateSvnPrice() internal {
        try IOracle(svnOracle).update() {} catch {}
    }

    modifier checkCondition() {
        require(now >= startTime, "Treasury: not started yet");
        _;
    }

    modifier checkEpoch() {
        require(now >= nextEpochPoint(), "Treasury: not opened yet");
        _;
        epoch = epoch.add(1);
        epochSupplyContractionLeft = (getSvnPrice() > svnPriceCeiling)
            ? 0
            : getSvnCirculatingSupply().mul(maxSupplyContractionPercent).div(
                10000
            );
    }

    modifier checkOperator() {
        require(
            IBasisAsset(svn).operator() == address(this) &&
                IBasisAsset(svnbond).operator() == address(this) &&
                IBasisAsset(svnshare).operator() == address(this) &&
                Operator(svnWheel).operator() == address(this),
            "Treasury: need more permission"
        );
        _;
    }

    modifier notInitialized() {
        require(!initialized, "Treasury: already initialized");
        _;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "Treasury: caller is not the operator");
        _;
    }
}
