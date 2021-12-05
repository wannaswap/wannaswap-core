// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
import "../libraries/BoringMath.sol";
import "../libraries/BoringERC20.sol";

import "../interfaces/IWannaSwapERC20.sol";
import "../interfaces/IWannaSwapPair.sol";
import "../interfaces/IWannaSwapFactory.sol";

import "./BoringOwnable.sol";

contract WannaConvertFee is BoringOwnable {
    using BoringMath for uint256;
    using BoringERC20 for IERC20;

    IWannaSwapFactory public immutable factory;
    // 0x7928D4FeA7b2c90C732c10aFF59cf403f0C38246
    address public immutable wannax;
    // 0x5205c30bf2E37494F8cF77D2c19C6BA4d2778B9B
    address private immutable wanna;
    // 0x7faA64Faf54750a2E3eE621166635fEAF406Ab22
    address private immutable weth;
    // 0xC9BdeEd33CD01541e1eeD10f90519d2C06Fe3feB
    address private immutable wnear;
    // 0xC42C30aC6Cc15faC9bD938618BcaA1a1FaE8501d

    mapping(address => address) internal _bridges;

    event LogBridgeSet(address indexed token, address indexed bridge);
    event LogConvertSingleToken(
        address indexed server,
        address indexed token,
        uint256 amount,
        uint256 amountWANNA
    );
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountWANNA
    );

    constructor(
        address _factory,
        address _wannax,
        address _wanna,
        address _weth,
        address _wnear
    ) public {
        factory = IWannaSwapFactory(_factory);
        wannax = _wannax;
        wanna = _wanna;
        weth = _weth;
        wnear = _wnear;
    }

    receive() external payable {
        assert(msg.sender == weth); // only accept ETH via fallback from the WETH contract
    }

    function bridgeFor(address token) public view returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = weth;
        }
    }

    function setBridge(address token, address bridge) external onlyOwner {
        require(
            token != wanna && token != weth && token != wnear && token != bridge,
            "WannaConvertFee: Invalid bridge"
        );

        _bridges[token] = bridge;
        emit LogBridgeSet(token, bridge);
    }

    function convertSingleToken(address token) external {
        uint256 amount = IERC20(token).balanceOf(address(this));
        emit LogConvertSingleToken(
            msg.sender,
            token,
            amount,
            _toWANNA(token, amount)
        );
    }

    function convertMultipleSingleToken(
        address[] calldata token
    ) external {
        uint256 len = token.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 amount = IERC20(token[i]).balanceOf(address(this));
            emit LogConvertSingleToken(
                msg.sender,
                token[i],
                amount,
                _toWANNA(token[i], amount)
            );
        }
    }

    function convert(address token0, address token1) external {
        _convert(token0, token1);
    }

    function convertMultiple(
        address[] calldata token0,
        address[] calldata token1
    ) external {
        uint256 len = token0.length;
        for (uint256 i = 0; i < len; i++) {
            _convert(token0[i], token1[i]);
        }
    }

    function _convert(address token0, address token1) internal {
        IWannaSwapPair pair = IWannaSwapPair(factory.getPair(token0, token1));
        if (address(pair) != address(0) && pair.balanceOf(address(this)) > 0) {
            IERC20(address(pair)).safeTransfer(
                address(pair),
                pair.balanceOf(address(this))
            );

            (uint256 amount0, uint256 amount1) = pair.burn(address(this));
            if (token0 != pair.token0()) {
                (amount0, amount1) = (amount1, amount0);
            }
            emit LogConvert(
                msg.sender,
                token0,
                token1,
                amount0,
                amount1,
                _convertStep(token0, token1, amount0, amount1)
            );
        }
    }

    function _convertStep(address token0, address token1, uint256 amount0, uint256 amount1) internal returns(uint256 wannaOut) {
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == wanna) {
                IERC20(wanna).safeTransfer(wannax, amount);
                wannaOut = amount;
            } else if (token0 == weth) {
                wannaOut = _toWANNA(weth, amount);
            } else if (token0 == wnear) {
                wannaOut = _toWANNA(wnear, amount);
            } else {
                address bridge = bridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this));
                wannaOut = _convertStep(bridge, bridge, amount, 0);
            }
        } else if (token0 == wanna) { // eg. WANNA - ETH
            IERC20(wanna).safeTransfer(wannax, amount0);
            wannaOut = _toWANNA(token1, amount1).add(amount0);
        } else if (token1 == wanna) { // eg. USDC- WANNA
            IERC20(wanna).safeTransfer(wannax, amount1);
            wannaOut = _toWANNA(token0, amount0).add(amount1);
        } else if (token0 == weth) { // eg. ETH - USDC
            wannaOut = _toWANNA(weth, _swap(token1, weth, amount1, address(this)).add(amount0));
        } else if (token1 == weth) { // eg. USDC - ETH
            wannaOut = _toWANNA(weth, _swap(token0, weth, amount0, address(this)).add(amount1));
        } else if (token0 == wnear) { // eg. wNEAR - USDC
            wannaOut = _toWANNA(wnear, _swap(token1, wnear, amount1, address(this)).add(amount0));
        } else if (token1 == wnear) { // eg. USDC - wNEAR
            wannaOut = _toWANNA(wnear, _swap(token0, wnear, amount0, address(this)).add(amount1));
        } else { // eg. AURORA - USDC
            address bridge0 = bridgeFor(token0);
            address bridge1 = bridgeFor(token1);
            if (bridge0 == token1) { // eg. AURORA - USDC - and bridgeFor(AURORA) = USDC
                wannaOut = _convertStep(bridge0, token1,
                    _swap(token0, bridge0, amount0, address(this)),
                    amount1
                );
            } else if (bridge1 == token0) { // eg. WBTC - SNX - and bridgeFor(SNX) = WBTC
                wannaOut = _convertStep(token0, bridge1,
                    amount0,
                    _swap(token1, bridge1, amount1, address(this))
                );
            } else {
                wannaOut = _convertStep(bridge0, bridge1, // eg. USDC - SNX - and bridgeFor(SNX) = WBTC
                    _swap(token0, bridge0, amount0, address(this)),
                    _swap(token1, bridge1, amount1, address(this))
                );
            }
        }
    }

    function _swap(address fromToken, address toToken, uint256 amountIn, address to) internal returns (uint256 amountOut) {
        IWannaSwapPair pair = IWannaSwapPair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "WannaConvertFee: Cannot convert");

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(998);
        if (fromToken == pair.token0()) {
            amountOut = amountIn.mul(998).mul(reserve1) / reserve0.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(0, amountOut, to, new bytes(0));
        } else {
            amountOut = amountIn.mul(998).mul(reserve0) / reserve1.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(amountOut, 0, to, new bytes(0));
        }
    }

    function _toWANNA(address token, uint256 amountIn) internal returns(uint256 amountOut) {
        amountOut = _swap(token, wanna, amountIn, wannax);
    }
}