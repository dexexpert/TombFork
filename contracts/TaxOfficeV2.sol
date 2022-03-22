// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Operator.sol";
import "./ITaxable.sol";
import "./IPancakeV2Router.sol";

contract TaxOfficeV2 is Operator {
    using SafeMath for uint256;

    address public svn;
    address public router;
    mapping(address => bool) public taxExclusionEnabled;

    function taxRate() external view returns (uint256) {
        return ITaxable(svn).taxRate();
    }

    constructor(address _svn, address _router) public {
        require(_svn != address(0), "svn address cannot be 0");
        require(_router != address(0), "router address cannot be 0");
        svn = _svn;
        router = _router;
    }

    function addLiquidityETHTaxFree(
        uint256 amtSvn,
        uint256 amtSvnMin,
        uint256 amtFtmMin
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtSvn != 0 && msg.value != 0, "amounts can't be 0");
        uint256 resultAmtSvn;
        uint256 resultAmtFtm;
        uint256 liquidity;
        _excludeAddressFromTax(msg.sender);
        IERC20(svn).transferFrom(msg.sender, address(this), amtSvn);
        _approveTokenIfNeeded(svn, router);
        _includeAddressInTax(msg.sender);
        (resultAmtSvn, resultAmtFtm, liquidity) = IPancakeRouter02(router)
            .addLiquidityETH{value: msg.value}(
            svn,
            amtSvn,
            amtSvnMin,
            amtFtmMin,
            msg.sender,
            block.timestamp
        );
        if (amtSvn.sub(resultAmtSvn) > 0) {
            IERC20(svn).transfer(msg.sender, amtSvn.sub(resultAmtSvn));
        }
        return (resultAmtSvn, resultAmtFtm, liquidity);
    }

    function addLiquidityTaxFree(
        address token,
        uint256 amtSvn,
        uint256 amtToken,
        uint256 amtSvnMin,
        uint256 amtTokenMin
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtSvn != 0 && amtToken != 0, "amounts can't be 0");
        uint256 resultAmtSvn;
        uint256 resultAmtToken;
        uint256 liquidity;
        _excludeAddressFromTax(msg.sender);
        IERC20(svn).transferFrom(msg.sender, address(this), amtSvn);
        IERC20(token).transferFrom(msg.sender, address(this), amtToken);
        _approveTokenIfNeeded(svn, router);
        _approveTokenIfNeeded(token, router);
        _includeAddressInTax(msg.sender);
        (resultAmtSvn, resultAmtToken, liquidity) = IPancakeRouter02(router)
            .addLiquidity(
                svn,
                token,
                amtSvn,
                amtToken,
                amtSvnMin,
                amtTokenMin,
                msg.sender,
                block.timestamp
            );
        if (amtSvn.sub(resultAmtSvn) > 0) {
            IERC20(svn).transfer(msg.sender, amtSvn.sub(resultAmtSvn));
        }
        if (amtToken.sub(resultAmtToken) > 0) {
            IERC20(token).transfer(msg.sender, amtToken.sub(resultAmtToken));
        }
        return (resultAmtSvn, resultAmtToken, liquidity);
    }

    function disableAutoCalculateTax() external onlyOperator {
        ITaxable(svn).disableAutoCalculateTax();
    }

    function enableAutoCalculateTax() external onlyOperator {
        ITaxable(svn).enableAutoCalculateTax();
    }

    function excludeAddressFromTax(address _address)
        external
        onlyOperator
        returns (bool)
    {
        return _excludeAddressFromTax(_address);
    }

    function includeAddressInTax(address _address)
        external
        onlyOperator
        returns (bool)
    {
        return _includeAddressInTax(_address);
    }

    function setBurnThreshold(uint256 _burnThreshold) external onlyOperator {
        ITaxable(svn).setBurnThreshold(_burnThreshold);
    }

    function setTaxCollectorAddress(address _taxCollectorAddress)
        external
        onlyOperator
    {
        ITaxable(svn).setTaxCollectorAddress(_taxCollectorAddress);
    }

    function setTaxExclusionForAddress(address _address, bool _excluded)
        external
        onlyOperator
    {
        taxExclusionEnabled[_address] = _excluded;
    }

    function setTaxRate(uint256 _taxRate) external onlyOperator {
        ITaxable(svn).setTaxRate(_taxRate);
    }

    function setTaxTiersRate(uint8 _index, uint256 _value)
        external
        onlyOperator
        returns (bool)
    {
        return ITaxable(svn).setTaxTiersRate(_index, _value);
    }

    function setTaxTiersTwap(uint8 _index, uint256 _value)
        external
        onlyOperator
        returns (bool)
    {
        return ITaxable(svn).setTaxTiersTwap(_index, _value);
    }

    function setTaxableSvnOracle(address _svnOracle) external onlyOperator {
        ITaxable(svn).setSvnOracle(_svnOracle);
    }

    function taxFreeTransferFrom(
        address _sender,
        address _recipient,
        uint256 _amt
    ) external {
        require(
            taxExclusionEnabled[msg.sender],
            "Address not approved for tax free transfers"
        );
        _excludeAddressFromTax(_sender);
        IERC20(svn).transferFrom(_sender, _recipient, _amt);
        _includeAddressInTax(_sender);
    }

    function transferTaxOffice(address _newTaxOffice) external onlyOperator {
        ITaxable(svn).setTaxOffice(_newTaxOffice);
    }

    function _approveTokenIfNeeded(address _token, address _router) private {
        if (IERC20(_token).allowance(address(this), _router) == 0) {
            IERC20(_token).approve(_router, type(uint256).max);
        }
    }

    function _excludeAddressFromTax(address _address) private returns (bool) {
        if (!ITaxable(svn).isAddressExcluded(_address)) {
            return ITaxable(svn).excludeAddress(_address);
        }
    }

    function _includeAddressInTax(address _address) private returns (bool) {
        if (ITaxable(svn).isAddressExcluded(_address)) {
            return ITaxable(svn).includeAddress(_address);
        }
    }
}
