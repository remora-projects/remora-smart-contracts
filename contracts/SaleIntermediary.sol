// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title RemoraSaleIntermediary
 * @notice A contract to act as a sale intermediary for exchanging stablecoins for RWA tokens or swapping payment tokens.
 * @dev Compatible with OpenZeppelin Upgradeable contracts.
 */
contract RemoraSaleIntermediary is
    Initializable,
    ReentrancyGuardUpgradeable,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    /**
     * @notice Emitted on a successful swap of one token for another.
     * @param initiator The address initiating the swap.
     * @param swapFromAddress The address of the token being swapped from.
     * @param fromAmount The amount of the token being swapped from.
     * @param swapToAddress The address of the token being swapped to.
     * @param toAmount The amount of the token being swapped to.
     */
    event SwapSuccess(
        address initiator,
        address counterparty,
        address swapFromAddress,
        uint256 fromAmount,
        address swapToAddress,
        uint256 toAmount
    );

    /// @notice Error when an invalid address is sent.
    error InvalidAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with access manager address.
     * @param initialAuthority The address of the AccessManager.
     */
    function initialize(address initialAuthority) public initializer {
        __ReentrancyGuard_init();
        __AccessManaged_init(initialAuthority);
        __UUPSUpgradeable_init();
    }

    /**
     * @notice Facilitates the swap of one type of token for another.
     * @dev Both parties must 'approve' or 'permit' funds to the contract before calling this function.
     * @param initiator The address initiating the swap.
     * @param counterparty The address of the counterparty providing the alternate token.
     * @param fromPaymentAddress The address of the token being swapped from.
     * @param toPaymentAddress The address of the token being swapped to.
     * @param fromAmount The amount of the token being swapped from.
     * @param toAmount The amount of the token being swapped to.
     */
    function facilitateSwap(
        address initiator,
        address counterparty,
        address fromPaymentAddress,
        address toPaymentAddress,
        uint256 fromAmount,
        uint256 toAmount
    ) external restricted nonReentrant {
        if (
            fromPaymentAddress == address(0) ||
            toPaymentAddress == address(0) ||
            initiator == address(0) ||
            counterparty == address(0)
        ) revert InvalidAddress();

        IERC20 fromToken = IERC20(fromPaymentAddress);
        IERC20 toToken = IERC20(toPaymentAddress);

        // Step 1: Transfer 'from' payment from initiator to counterparty
        SafeERC20.safeTransferFrom(
            fromToken,
            initiator,
            counterparty,
            fromAmount
        );

        // Step 2: Transfer 'to' payment from counterparty to the initiator
        SafeERC20.safeTransferFrom(toToken, counterparty, initiator, toAmount);

        emit SwapSuccess(
            initiator,
            counterparty,
            fromPaymentAddress,
            fromAmount,
            toPaymentAddress,
            toAmount
        );
    }

    /**
     * @notice Used to upgrade smart contract. Restricted to authorized accounts.
     * @param newImplementation The address of the new implementation to be upgraded to.
     * @param data The data used for initializing the new contract.
     */
    function upgradeToAndCall(
        address newImplementation,
        bytes memory data
    ) public payable override restricted {
        super.upgradeToAndCall(newImplementation, data);
    }

    /**
     * @notice Authorizes upgrades for the contract.
     * @dev Override required by solidity.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override {}
}
