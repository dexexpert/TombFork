// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IPancakePair.sol";
import "./IPancakeV2Router.sol";
import "./IWBNB.sol";

contract SvnZapper is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public svn;
    address public mshare;
    IPancakeRouter02 public router;
    address public wbnb;

    constructor(
        address svn_,
        address mshare_,
        address router_,
        address wbnb_
    ) public Ownable() {
        address zero = address(0);
        require(svn_ != zero, "SvnZapper: Svn is zero address");
        require(mshare_ != zero, "SvnZapper: MShare is zero address");
        require(router_ != zero, "SvnZapper: Router is zero address");
        require(wbnb_ != zero, "SvnZapper: Wrapped is zero address");
        router = IPancakeRouter02(router_);
        svn = svn_;
        mshare = mshare_;
        wbnb = wbnb_;
    }

    function withdraw(address token) external onlyOwner returns (bool success) {
        success = true;
        if (token == address(0)) {
            msg.sender.transfer(address(this).balance);
            return success;
        }
        IERC20 token_ = IERC20(token);
        token_.safeTransfer(msg.sender, token_.balanceOf(address(this)));
    }

    function zapIn(address to) external payable returns (uint256 liquidity) {
        require(to == svn || to == mshare, "SvnZapper: Unsupported 'to' token");
        uint256 amountIn = msg.value;
        if (amountIn == 0) return 0;
        IWBNB(wbnb).deposit{value: amountIn}();
        liquidity = _zapInFromWFTM(to);
    }

    function zapInToken(
        address to,
        address from,
        uint256 amount
    ) external returns (uint256 liquidity) {
        require(to == svn || to == mshare, "SvnZapper: Unsupported 'to' token");
        if (amount == 0) return 0;
        IERC20(from).safeTransferFrom(msg.sender, address(this), amount);
        if (from != wbnb) _swap(from, wbnb, amount);
        liquidity = _zapInFromWFTM(to);
    }

    function _addLiquidity(
        address token0,
        address token1,
        uint256 amountIn0,
        uint256 amountIn1
    ) private returns (uint256 liquidity) {
        _approveIfNeeded(token0, address(router), amountIn0);
        _approveIfNeeded(token1, address(router), amountIn1);
        (, , liquidity) = router.addLiquidity(
            token0,
            token1,
            amountIn0,
            amountIn1,
            1,
            1,
            msg.sender,
            block.timestamp
        );
    }

    function _approveIfNeeded(
        address token,
        address target,
        uint256 amount
    ) private {
        IERC20 token_ = IERC20(token);
        if (token_.allowance(address(this), target) < amount)
            token_.safeApprove(target, type(uint256).max);
    }

    function _returnAssets(address[] memory tokens) private {
        address caller = msg.sender;
        address this_ = address(this);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 balance = IERC20(token).balanceOf(this_);
            if (balance > 0) token.safeTransfer(caller, balance);
        }
    }

    function _swap(
        address from,
        address to,
        uint256 amountIn
    ) private returns (uint256 result, address[] memory path) {
        _approveIfNeeded(from, address(router), amountIn);
        path = new address[](2);
        path[0] = from;
        path[1] = to;
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            1,
            path,
            address(this),
            block.timestamp
        );
        result = amounts[amounts.length - 1];
    }

    function _zapInFromWFTM(address to) internal returns (uint256 liquidity) {
        uint256 halfAmount = IERC20(wbnb).balanceOf(address(this)).div(2);
        (uint256 toAmount, address[] memory path) = _swap(wbnb, to, halfAmount);
        liquidity = _addLiquidity(wbnb, to, halfAmount, toAmount);
        _returnAssets(path);
    }
}
