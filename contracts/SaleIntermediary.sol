// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

interface IRwaToken {
    function adminClaimPayout(address, bool, bool, uint256) external;

    function adminTransferFrom(
        address,
        address,
        uint256,
        bool,
        bool
    ) external returns (bool);

    function burnFrom(address, uint256) external;
}

/**
 * @title RemoraSaleIntermediary
 * @notice A contract to act as a sale intermediary for exchanging stablecoins for RWA tokens or swapping payment tokens.
 */
contract RemoraSaleIntermediary is AccessManaged, ReentrancyGuard {
    address private _feeRecipient;
    address private _fundingWallet;

    /// @notice Error when an invalid address is sent.
    error InvalidAddress();

    /**
     * @param seller The address of the the seller.
     * @param buyer The address of the buyer.
     * @param assetSold The token the seller is providing.
     * @param assetReceived The token the buyer is providing.
     * @param feeToken The address of the token to be used to pay the fee.
     * @param hasSellerFee Boolean flag for fees.
     * @param assetSoldAmount The amount of the token the seller is selling.
     * @param assetReceivedAmount The amount of the token the buyer is paying.
     * @param feeAmount The amount in tokens of the fee.
     */
    struct TradeData {
        address seller;
        address buyer;
        address assetSold;
        address assetReceived;
        address feeToken;
        bool hasSellerFee;
        uint128 assetSoldAmount;
        uint128 assetReceivedAmount;
        uint128 feeAmount;
    }

    /**
     * @param holder The address of the token holder claiming the payout.
     * @param rwaToken The address of the RWA Token that the holder is collecting payout from.
     * @param paymentToken The address of the ERC20 token that the holder will be paid out in.
     * @param useCustomFee A value indicating whether or not to use a custom fee when user is claiming payout.
     * @param paymentTokenAmount The amount of the payment token the holder will recieve.
     * @param feeValue The value of the fee, used to calculate proper amount for the event emitted in adminClaimPayout.
     * ^ feeValue must always be in USD (6 decimals)
     */
    struct PayoutData {
        address holder;
        address rwaToken;
        address paymentToken;
        bool useCustomFee;
        uint128 paymentTokenAmount;
        uint128 feeValue;
    }

    /**
     * @param holder The address of the token holder whose tokens are to be burned.
     * @param rwaToken The address of the RWA Token that the holder is trying to burn.
     * @param paymentToken The address of the ERC20 token that the holder will be paid out in.
     * @param rwaBurnAmount The number of RWA Tokens to be burned.
     * @param paymentTokenAmount The amount of the payment token the holder will recieve.
     */
    struct BurnData {
        address holder;
        address rwaToken;
        address paymentToken;
        uint256 rwaBurnAmount;
        uint256 paymentAmount;
    }

    /**
     * @notice Initializes the contract with access manager address.
     * @param initialAuthority The address of the AccessManager.
     * @param feeRecipient The address where fees are paid out to.
     */
    constructor(
        address initialAuthority,
        address fundingWallet,
        address feeRecipient
    ) AccessManaged(initialAuthority) ReentrancyGuard() {
        _fundingWallet = fundingWallet;
        _feeRecipient = feeRecipient;
    }

    /**
     * @notice Sets a new address as the funding wallet
     * @param newWallet The address of the new funding wallet.
     */
    function setFundingWallet(address newWallet) external restricted {
        if (newWallet == address(0)) revert InvalidAddress();
        _fundingWallet = newWallet;
    }

    /**
     * @notice Sets a new address as the fee recipient
     * @param newRecipient The address of the new fee recpient
     */
    function setFeeRecipient(address newRecipient) external restricted {
        if (newRecipient == address(0)) revert InvalidAddress();
        _feeRecipient = newRecipient;
    }

    /**
     * @notice Facilitates the swap of one type of token for another. (most likely wont need this)
     * @dev Both parties must 'approve' or 'permit' funds to the contract before calling this function.
     * @param data The struct containing the data for the function.
     */
    function swapTokens(
        TradeData calldata data
    ) external restricted nonReentrant {
        address seller = data.seller;
        address buyer = data.buyer;
        _validateAddresses(seller, buyer, data.assetReceived, data.assetSold);

        if (data.hasSellerFee)
            _chargeFee(buyer, _feeRecipient, data.feeToken, data.feeAmount);

        IERC20(data.assetReceived).transferFrom(
            buyer,
            seller,
            data.assetReceivedAmount
        );
        IERC20(data.assetSold).transferFrom(
            seller,
            buyer,
            data.assetSoldAmount
        );
    }

    /**
     * @notice Facilitates the transfer of Remora RWA token for payment token.
     * @dev Both parties must 'approve' or 'permit' funds to the contract before calling this function.
     * @param data The struct containing the data for the function.
     */
    function processRwaSale(
        TradeData calldata data
    ) external restricted nonReentrant {
        address seller = data.seller;
        address buyer = data.buyer;
        _validateAddresses(seller, buyer, data.assetSold, data.assetReceived);

        IERC20(data.assetReceived).transferFrom(
            buyer,
            seller,
            data.assetReceivedAmount
        );
        if (data.hasSellerFee)
            _chargeFee(seller, _feeRecipient, data.feeToken, data.feeAmount);

        IRwaToken(data.assetSold).adminTransferFrom(
            seller,
            buyer,
            data.assetSoldAmount,
            true,
            true
        );
    }

    /**
     * @notice Calls adminPayoutClaim from RWAToken contract and pays out the holder.
     * @param data The struct containing the data for the function.
     */
    function processPayout(
        PayoutData calldata data
    ) external restricted nonReentrant {
        address holder = data.holder;

        _validateAddresses(
            holder,
            data.rwaToken,
            data.paymentToken,
            address(1)
        );

        IRwaToken(data.rwaToken).adminClaimPayout(
            holder,
            false,
            data.useCustomFee,
            data.feeValue
        );

        IERC20(data.paymentToken).transferFrom(
            _fundingWallet,
            holder,
            data.paymentTokenAmount
        );
    }

    /**
     * @notice Facilitates the burning and payout of RWA tokens.
     * @dev The holder must approve the RWA tokens to burn, and the _fundingWallet must approve the tokens to transfer.
     * @param data The struct containing the data for the function.
     */
    function processBurn(
        BurnData calldata data
    ) external restricted nonReentrant {
        address holder = data.holder;

        _validateAddresses(
            holder,
            data.rwaToken,
            data.paymentToken,
            address(1)
        );

        IRwaToken(data.rwaToken).burnFrom(holder, data.rwaBurnAmount);

        IERC20(data.paymentToken).transferFrom(
            _fundingWallet,
            holder,
            data.paymentAmount
        );
    }

    function _validateAddresses(
        address a,
        address b,
        address c,
        address d
    ) internal pure {
        if (
            a == address(0) ||
            b == address(0) ||
            c == address(0) ||
            d == address(0)
        ) revert InvalidAddress();
    }

    function _chargeFee(
        address payer,
        address recipient,
        address token,
        uint256 amount
    ) internal {
        if (token == address(0) || recipient == address(0))
            revert InvalidAddress();
        IERC20(token).transferFrom(payer, recipient, amount);
    }
}
