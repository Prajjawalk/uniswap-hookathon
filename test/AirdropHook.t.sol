// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Airdrop} from "../src/AirdropHook.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IRouterClient, WETH9, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {console} from "forge-std/console.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AirdropTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    CCIPLocalSimulator public ccipLocalSimulator;

    Airdrop hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    struct Receiver {
      uint256 chainId;
      address receiver;
    }

    // Test constants for CCIP
    uint64 DESTINATION_CHAIN_SELECTOR; // Example: Sepolia
    address constant MOCK_RECEIVER = 0xdD69DB25F6D620A7baD3023c5d32761D353D3De9;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        ccipLocalSimulator = new CCIPLocalSimulator();

        (
            uint64 chainSelector,
            IRouterClient sourceRouter,
            IRouterClient destinationRouter,
            WETH9 wrappedNative,
            LinkToken linkToken,
            BurnMintERC677Helper ccipBnM,
            BurnMintERC677Helper ccipLnM
        ) = ccipLocalSimulator.configuration();

        DESTINATION_CHAIN_SELECTOR = chainSelector;

        deployAndApprovePosm(manager);


        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.AFTER_SWAP_FLAG
            ) ^ (0x4444 << 144));
        bytes memory constructorArgs = abi.encode(manager, sourceRouter); //Add all the necessary constructor arguments from the hook
        deployCodeTo("AirdropHook.sol:Airdrop", constructorArgs, flags);
        hook = Airdrop(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 10000e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );

        // Mint tokens to the hook contract for swapping
        IERC20(Currency.unwrap(currency0)).transfer(address(hook), 1_000_000e18);
        IERC20(Currency.unwrap(currency1)).transfer(address(hook), 1_000_000e18);
    }

    function testAirdropAfterSwap() public {
        // Setup the receiver data
        Receiver memory receiver = Receiver({
            chainId: DESTINATION_CHAIN_SELECTOR,
            receiver: MOCK_RECEIVER
        });
        
        // Encode the receiver data for the swap
        bytes memory swapData = abi.encode(receiver);
        
        // Perform swap with receiver data
        bool zeroForOne = true;
        int256 amountSpecified = -1e18;
        
        // Fund the hook with ETHER for CCIP fees
        deal(address(hook), 1 ether);
        
        // Perform the swap
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, swapData);
        
        // Verify swap occurred correctly
        assertEq(int256(swapDelta.amount0()), amountSpecified);
    }
    
    // Optional: Test failure cases
    function testFailsWithoutLinkBalance() public {
        Receiver memory receiver = Receiver({
            chainId: DESTINATION_CHAIN_SELECTOR,
            receiver: MOCK_RECEIVER
        });
        
        bytes memory swapData = abi.encode(receiver);
        bool zeroForOne = true;
        int256 amountSpecified = -1e18;
        
        // Don't fund the hook with LINK
        // This should revert due to insufficient LINK balance
        vm.expectRevert();
        swap(key, zeroForOne, amountSpecified, swapData);
    }
}