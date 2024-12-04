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

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
  
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
      uint256 postSwapBalance;
      uint256 amountPerAddress;
      Currency toSend;
    }

    struct Receiver {
      uint256 chainId;
      address receiver;
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata swapParams, BalanceDelta delta, bytes calldata hookData)
        external
        override
        returns (bytes4, int128)
    {
        
        MyData memory data = MyData({
          amount: 0,
          postSwapBalance: 0,
          amountPerAddress: 0,
          toSend: Currency.wrap(address(0))
        });

        if(swapParams.zeroForOne) {
          data.toSend = (key.currency1);
          data.amount = delta.amount1();
        } else {
          data.toSend = key.currency0;
          data.amount = delta.amount0();
        }

        // 5% of the output as airdrop with max cap of 100 tokens
        uint256 airdropAmount = Math.min(uint256(stdMath.abs(data.amount)) / 20, 100 * uint256(ERC20(Currency.unwrap(data.toSend)).decimals()));

        // Airdrop if balance is sufficient
        if (ERC20(Currency.unwrap(data.toSend)).balanceOf(address(this)) >=  uint256(stdMath.abs(data.amount)) + airdropAmount) {
          IERC20(Currency.unwrap(data.toSend)).transfer(msg.sender, airdropAmount);
        }

        return (BaseHook.afterSwap.selector, 0);
    }
}