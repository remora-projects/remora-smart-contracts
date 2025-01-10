// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title RemoraSaleIntermediary
 * @notice A contract to act as a sale intermediary for exchanging stablecoins for RWA tokens or swapping payment tokens.
 * @dev Compatible with OpenZeppelin Upgradeable contracts.
 */
contract RemoraSaleIntermediary is Initializable, ReentrancyGuardUpgradeable, AccessManagedUpgradeable, UUPSUpgradeable {
    /**
     * @notice Mapping of RWA token IDs to their respective token addresses.
     * @dev RWA token IDs come from the database.
     */
    mapping(uint256 => IERC20) public rwaTokens;

    /**
     * @notice Mapping of payment token IDs to their respective token addresses.
     * @dev Payment token IDs come from the database.
     */
    mapping(uint256 => IERC20) public paymentTokens;

    /// @notice Emitted when a new payment token is added.
    event PaymentTokenAdded(uint256 id, address tokenAddress);

    /// @notice Emitted when a new RWA token is added.
    event RWATokenAdded(uint256 id, address rwaAddress);

    /**
     * @notice Emitted on a successful transfer of RWA tokens for payment tokens.
     * @param buyer The address of the buyer.
     * @param seller The address of the seller.
     * @param rwaId The ID of the RWA token being transferred.
     * @param rwaTokenAmount The amount of RWA tokens transferred.
     * @param paymentId The ID of the payment token used.
     * @param paymentAmount The amount of payment tokens transferred.
     */
    event TransferSuccess(
        address buyer,
        address seller,
        uint256 rwaId, 
        uint256 rwaTokenAmount, 
        uint256 paymentId, 
        uint256 paymentAmount
    );
    
    /**
     * @notice Emitted on a successful swap of one payment token for another.
     * @param initiator The address initiating the swap.
     * @param swapFromId The ID of the payment token being swapped from.
     * @param fromAmount The amount of the token being swapped from.
     * @param swapToId The ID of the payment token being swapped to.
     * @param toAmount The amount of the token being swapped to.
     */
    event SwapSuccess(
        address initiator,  
        uint256 swapFromId, 
        uint256 fromAmount, 
        uint256 swapToId, 
        uint256 toAmount
    );

    /// @notice Reverted if a token transfer fails.
    error TransferFromFailed(address token, address participant, uint256 amount);

    /// @notice Reverted if an invalid token address is provided.
    error InvalidTokenAddress(uint256 id);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with initial mappings for RWA and payment tokens.
     * @param initialAuthority The address of the AccessManager.
     * @param rwaIds The list of RWA token IDs.
     * @param rwaAddresses The list of RWA token addresses.
     * @param paymentIds The list of payment token IDs.
     * @param paymentAddresses The list of payment token addresses.
     */
    function initialize(
        address initialAuthority, 
        uint256[] calldata rwaIds, 
        address[] calldata rwaAddresses, 
        uint256[] calldata paymentIds, 
        address[] calldata paymentAddresses
    ) initializer public {
        __ReentrancyGuard_init();
        __AccessManaged_init(initialAuthority);
        __UUPSUpgradeable_init();

        uint256 rwaIdLen = rwaIds.length;
        uint256 rwaAddrLen = rwaAddresses.length;

        uint256 paymentIdLen = paymentIds.length;
        uint256 paymentAddrLen = paymentAddresses.length;

        assert(rwaIdLen == rwaAddrLen);
        assert(paymentIdLen == paymentAddrLen);

        for(uint256 i = 0; i < rwaIdLen; i++){
            rwaTokens[rwaIds[i]] = IERC20(rwaAddresses[i]);
        }

        for(uint256 j = 0; j < paymentIdLen; j++){
           paymentTokens[paymentIds[j]] = IERC20(paymentAddresses[j]);
        }
    }

    /**
     * @notice Adds or updates a payment token.
     * @param id The ID of the payment token.
     * @param newToken The address of the new payment token.
     */
    function addPaymentToken(uint256 id, address newToken) external restricted {
        paymentTokens[id] = IERC20(newToken);
        emit PaymentTokenAdded(id, newToken);
    }

    /**
     * @notice Adds or updates an RWA token.
     * @param id The ID of the RWA token.
     * @param newToken The address of the new RWA token.
     */
    function addRWAToken(uint256 id, address newToken) external restricted {
        rwaTokens[id] = IERC20(newToken);
        emit RWATokenAdded(id, newToken);
    }

    /**
     * @notice Facilitates the sale of RWA tokens for payment tokens.
     * @param buyer The address of the buyer.
     * @param seller The address of the seller.
     * @param rwaId The ID of the RWA token.
     * @param paymentId The ID of the payment token.
     * @param rwaTokenAmount The amount of RWA tokens being sold.
     * @param paymentAmount The amount of payment tokens being paid.
     */
    function facilitateSale(
        address buyer,
        address seller,
        uint256 rwaId, 
        uint256 paymentId, 
        uint256 rwaTokenAmount, 
        uint256 paymentAmount
    ) external restricted nonReentrant {
        IERC20 rwaToken = rwaTokens[rwaId];
        IERC20 paymentToken = paymentTokens[paymentId];

        assert(buyer != address(0) && seller != address(0));

        if(address(rwaToken) == address(0)){
            revert InvalidTokenAddress(rwaId);
        }

        if(address(paymentToken) == address(0)){
            revert InvalidTokenAddress(paymentId);
        }

        // Step 1: Transfer payment from buyer to seller
        if(!paymentToken.transferFrom(buyer, seller, paymentAmount)){
            revert TransferFromFailed(address(paymentToken), buyer, paymentAmount);
        }

        // Step 2: Transfer RWA tokens from seller to the buyer
        if(!rwaToken.transferFrom(seller, buyer, rwaTokenAmount)){
            revert TransferFromFailed(address(rwaToken), buyer, rwaTokenAmount);
        }

        emit TransferSuccess(buyer, seller, rwaId, rwaTokenAmount, paymentId, paymentAmount);
    }

    /**
     * @notice Facilitates the swap of one payment token for another.
     * @param initiator The address initiating the swap.
     * @param counterparty The address of the counterparty providing the alternate payment.
     * @param fromPaymentId The ID of the token being swapped from.
     * @param toPaymentId The ID of the token being swapped to.
     * @param fromAmount The amount of the token being swapped from.
     * @param toAmount The amount of the token being swapped to.
     */
    function facilitateSwap(
        address initiator, 
        address counterparty,
        uint256 fromPaymentId, 
        uint256 toPaymentId, 
        uint256 fromAmount, 
        uint256 toAmount
    ) external restricted nonReentrant {
        IERC20 fromToken = paymentTokens[fromPaymentId];
        IERC20 toToken = paymentTokens[toPaymentId];

        assert(initiator != address(0) && counterparty != address(0));

        if(address(fromToken) == address(0)){
            revert InvalidTokenAddress(fromPaymentId);
        }

        if(address(toToken) == address(0)){
            revert InvalidTokenAddress(toPaymentId);
        }

        // Step 1: Transfer 'from' payment from user to swapper
        if(!fromToken.transferFrom(initiator, counterparty, fromAmount)){
            revert TransferFromFailed(address(fromToken), initiator, fromAmount);
        }

        // Step 2: Transfer 'to' payment from seller to the buyer
        if(!toToken.transferFrom(counterparty, initiator, toAmount)){
            revert TransferFromFailed(address(toToken), counterparty, toAmount);
        }

        emit SwapSuccess(initiator, fromPaymentId, fromAmount, toPaymentId, toAmount);
    }

    /**
     * @notice Authorizes upgrades for the contract.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        restricted
        override
    {}
  }