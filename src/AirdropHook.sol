// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey, Currency} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {stdMath} from "forge-std/stdMath.sol";
import {console} from "forge-std/console.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Airdrop is BaseHook {
    using PoolIdLibrary for PoolKey;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    // mapping(PoolId => uint256 count) public beforeSwapCount;
    // mapping(PoolId => uint256 count) public afterSwapCount;

    // mapping(PoolId => uint256 count) public beforeAddLiquidityCount;
    // mapping(PoolId => uint256 count) public beforeRemoveLiquidityCount;
    // Mapping to store tokenB balances before the swap for each user
    // mapping(address => uint256) public preSwapBalances;

    IRouterClient public immutable router;
    
    constructor(IPoolManager _poolManager, address _router) BaseHook(_poolManager) {
        router = IRouterClient(_router);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------


    struct MyData {
      int128 amount;
      Currency toSend;
    }

    struct Receiver {
      uint64 destinationChainSelector;
      address receiver;
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        Receiver memory receiver = abi.decode(hookData, (Receiver));

        MyData memory data = MyData({
          amount: 0,
          toSend: Currency.wrap(address(0))
        });


        if(swapParams.zeroForOne) {
            data.toSend = (key.currency1);
            data.amount = delta.amount1();
        } else {
            data.toSend = key.currency0;
            data.amount = delta.amount0();
        }

        address tokenAddress = Currency.unwrap(data.toSend);
        uint256 swapAmount = uint256(stdMath.abs(data.amount));
        
        // Calculate 5% airdrop with max cap of 100 tokens
        uint256 airdropAmount = Math.min(
            swapAmount / 20, 
            100 * uint256(ERC20(tokenAddress).decimals())
        );

        // Total amount to send cross-chain (swap result + airdrop)
        uint256 totalAmount = swapAmount + airdropAmount;

        // // Check if contract has sufficient balance for both swap and airdrop
        require(
            ERC20(tokenAddress).balanceOf(address(this)) >= totalAmount,
            "Insufficient balance for swap + airdrop"
        );

        // Prepare CCIP message with total amount
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver.receiver),
            data: "",
            tokenAmounts: _buildTokenAmounts(tokenAddress, totalAmount),
            extraArgs: "",
            feeToken: address(0) // Use native for fees
        });

        // Approve router to spend tokens
        IERC20(tokenAddress).approve(address(router), totalAmount);

        // Send tokens cross-chain (including both swap result and airdrop)
        router.ccipSend(
            receiver.destinationChainSelector,
            message
        );

        return (BaseHook.afterSwap.selector, 0);
    }

    function _buildTokenAmounts(address token, uint256 amount) internal pure returns (Client.EVMTokenAmount[] memory) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: token,
            amount: amount
        });
        return tokenAmounts;
    }
}