// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TaxOracle is Ownable {
    using SafeMath for uint256;

    IERC20 public svn;
    IERC20 public wftm;
    address public pair;

    constructor(
        address _svn,
        address _wftm,
        address _pair
    ) public {
        require(_svn != address(0), "svn address cannot be 0");
        require(_wftm != address(0), "wftm address cannot be 0");
        require(_pair != address(0), "pair address cannot be 0");
        svn = IERC20(_svn);
        wftm = IERC20(_wftm);
        pair = _pair;
    }

    function consult(address _token, uint256 _amountIn)
        external
        view
        returns (uint144 amountOut)
    {
        require(_token == address(svn), "token needs to be svn");
        uint256 svnBalance = svn.balanceOf(pair);
        uint256 wftmBalance = wftm.balanceOf(pair);
        return uint144(svnBalance.mul(_amountIn).div(wftmBalance));
    }

    function getSvnBalance() external view returns (uint256) {
        return svn.balanceOf(pair);
    }

    function getWftmBalance() external view returns (uint256) {
        return wftm.balanceOf(pair);
    }

    function getPrice() external view returns (uint256) {
        uint256 svnBalance = svn.balanceOf(pair);
        uint256 wftmBalance = wftm.balanceOf(pair);
        return svnBalance.mul(1e18).div(wftmBalance);
    }

    function setSvn(address _svn) external onlyOwner returns (bool) {
        require(_svn != address(0), "svn address cannot be 0");
        svn = IERC20(_svn);
        return true;
    }

    function setWftm(address _wftm) external onlyOwner returns (bool) {
        require(_wftm != address(0), "wftm address cannot be 0");
        wftm = IERC20(_wftm);
        return true;
    }

    function setPair(address _pair) external onlyOwner returns (bool) {
        require(_pair != address(0), "pair address cannot be 0");
        pair = _pair;
        return true;
    }
}
