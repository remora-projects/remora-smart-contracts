// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "../IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardTransientUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

/// @custom:security-contact support@remora.us
/**
 * @title RemoraRWAHolderManagement
 * @notice This abstract contract facilitates payouts in stablecoins to token holders based on their balances.
 * It includes functionality for managing holders, distributing payouts, and withdrawing contract balances.
 * @dev This contract uses OpenZeppelin upgradeable utilities for modular and upgradeable design.
 */
abstract contract RemoraRWAHolderManagement is
    Initializable,
    ReentrancyGuardTransientUpgradeable,
    ContextUpgradeable, // AUDIT: do I need this?
    AccessManagedUpgradeable,
    ERC20Upgradeable
{
    /// @dev Contains token holder's data.
    struct HolderStatus {
        /// @dev The address this holder's payout should be forwarded to.
        address forwardPayoutTo;
        bool isFrozen;
        /// @dev Whether or not their payout balance has been previously calulated.
        bool isCalculated;
        /// @dev Whether or not the investor is token holder.
        bool isHolder;
        /// @dev Whether or not the holder has signed the terms and conditions.
        bool signedTC; //Must be true in order to recieve token
        /// @dev The index in which the user has been frozen.
        uint8 frozenIndex;
        uint8 lastPayoutIndexCalculated;
        /// @dev The index of the most recent entry in balance history.
        uint8 mostRecentEntry;
        /// @dev The timestamp of when the user was frozen. Used for 30 day calculation in adminTransferFrom in RemoraRWAToken.sol
        uint32 frozenTimestamp;
        /// @dev The value of the most recently calculated payout.
        uint256 calculatedPayout;
        /// @dev The addresses that are forwarding payouts to holder
        address[] forwardedPayouts;
    }

    /// @dev Contains info at the time of payout distribution
    struct PayoutInfo {
        uint128 amount; //could get away with this being smaller
        uint128 totalSupply;
    }

    /// @dev Contains holder's token balance and indicator of if entry is valid or not.
    struct TokenBalanceChange {
        bool isValid;
        uint256 tokenBalance;
    }

    /// @custom:storage-location erc7201:remora.storage.HolderManagement
    struct HolderManagementStorage {
        /// @dev The address of the wallet to which the contract's stablecoin balance can be withdrawn.
        address _wallet;
        /// @dev The IERC20 stablecoin used for facilitating payouts.
        IERC20 _stablecoin;
        /// @dev The fixed fee deducted from payouts, in USD, represented with 6 decimals.
        uint32 _payoutFee;
        /// @dev The current index that is yet to be paid out.
        uint8 _currentPayoutIndex;
        /// @dev mapping to a struct containing payout amounts and tokenSupply that the payout indices correlate to.
        mapping(uint256 => PayoutInfo) _payouts;
        /// @dev A mapping of token holder addresses to a struct containing holder info.
        mapping(address => HolderStatus) _holderStatus;
        /// @dev A mapping that links holder addresses to another mapping that links payout indices to TokenBalanceChange structs.
        mapping(address => mapping(uint8 => TokenBalanceChange)) _balanceHistory;
    }

    // keccak256(abi.encode(uint256(keccak256("remora.storage.HolderManagement")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant HolderManagementStorageLocation =
        0xd108a17532ee59ddb9baf9e5c8fe64833cf87c04e2b5867293af0a3e63efc200;

    /**
     * @notice Event emitted when the payout fee is updated.
     * @param newFee New value for the fixed payout fee.
     */
    event PayoutFeeUpdated(uint32 newFee);

    /**
     * @notice Event emitted when the stablecoin for payouts is updated.
     * @param newStablecoin Address of the ERC20 stablcoin contract.
     */
    event StablecoinChanged(address newStablecoin);

    /**
     * @notice Event emitted when a holder claims their payout.
     * @param holder The address of the holder.
     * @param amount The value of payout claimed.
     */
    event PayoutClaimed(address indexed holder, uint256 amount);

    /**
     * @notice Event emitted when payouts are distributed among token holders.
     * @param totalDistributed The total value of the payout distributed in USD stablecoin (6 decimals).
     */
    event PayoutDistributed(uint128 totalDistributed);

    /**
     * @notice Event emitted when a holder is frozen.
     * @param holder The address of the holder that has been frozen.
     */
    event HolderFrozen(address indexed holder);

    /**
     * @notice Event emitted when a holder is unfrozen.
     * @param holder The address of the holder that has been unfrozen.
     */
    event HolderUnfrozen(address indexed holder);

    /**
     * @notice Event emitted when a holder has signed the T&C
     * @param holder The address of the holder that has signed
     */
    event SignedTermsAndConditions(address indexed holder);

    /// @notice Error indicating that a holder attempted to claim payout when their available balance is zero.
    error NoPayoutToClaim(address holder);

    /// @notice Error indicating that the contract has insufficient stablecoin balance for the requested operation.
    error InsufficentStablecoinBalance();

    /// @notice Error indicating that a frozen user is restricted from the requested operation.
    error UserIsFrozen(address holder);

    /// @notice Error indicating that a user has not signed the terms and conditions.
    error TermsAndConditionsNotSigned(address holder);

    /// @notice Error indicating that a function was called with an invalid address.
    error InvalidAddress();

    /**
     * @notice Initializes the contract with the initial authority, stablecoin address, withdrawal wallet address, and fixed fee.
     * @dev Should be called during deployment or upgrade to set initial state.
     * @param _initialAuthority The address of the access manager contract.
     * @param _stablecoin The address of the stablecoin contract.
     * @param _wallet The address of the withdrawal wallet.
     * @param _payoutFee The fixed payout fee, in USD stablecoin, 6 decimals.
     */
    function __RemoraHolderManagement_init(
        address _initialAuthority,
        address _stablecoin,
        address _wallet,
        uint32 _payoutFee
    ) internal onlyInitializing {
        __AccessManaged_init(_initialAuthority);
        __ReentrancyGuardTransient_init();
        __RemoraHolderManagement_init_unchained(
            _stablecoin,
            _wallet,
            _payoutFee
        );
    }

    /**
     * @notice Sets the stablecoin, wallet, and fee value in the PayOut storage during initialization.
     * @dev Part of the initialization process.
     * @param _stablecoin The address of the stablecoin contract.
     * @param _wallet The address of the withdrawal wallet.
     * @param _payoutFee The fixed payout fee, in USD stablecoin, 6 decimals.
     */
    function __RemoraHolderManagement_init_unchained(
        address _stablecoin,
        address _wallet,
        uint32 _payoutFee
    ) internal onlyInitializing {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        $._stablecoin = IERC20(_stablecoin);
        $._wallet = _wallet;
        $._payoutFee = _payoutFee;
        $._currentPayoutIndex = 0;
    }

    /**
     * @notice Sets an address that is forwarded the holder's payout
     * @dev Main purpose is for when property tokens are held in a smart contract
     *      that shouldn't recieve rent (ex. liquidity pool)
     * @param holder The holder whose payout is being forwarded
     * @param forwardingAddress The address the payout is forwarded to
     */
    function setPayoutForwardAddress(
        address holder,
        address forwardingAddress
    ) external restricted {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        address curForwardAddr = $._holderStatus[holder].forwardPayoutTo;
        if (curForwardAddr != forwardingAddress) {
            _removePayoutForwardAddress($, holder, curForwardAddr);
            payoutBalance(holder); // call so any previous rent is kept by the holder
            $._holderStatus[holder].forwardPayoutTo = forwardingAddress;
            $._holderStatus[forwardingAddress].forwardedPayouts.push(holder);
        }
    }

    /**
     * @notice Removes rent forwarding
     * @dev Each holder only forwards to one account, external function with restriction
     * @param holder The holder whose payouts should no longer be forwarded
     */
    function removePayoutForwardAddress(address holder) external restricted {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        _removePayoutForwardAddress(
            $,
            holder,
            $._holderStatus[holder].forwardPayoutTo
        );
    }

    /**
     * @notice Removes rent forwarding
     * @dev Each holder only forwards to one account, internal function without restriction
     * @param $ contract storage
     * @param holder The holder whose payouts should no longer be forwarded
     */
    function _removePayoutForwardAddress(
        HolderManagementStorage storage $,
        address holder,
        address forwardedAddress
    ) internal {
        if (forwardedAddress != address(0)) {
            uint256 holderPayout = payoutBalance(holder); // call so any uncalculated rent is given to forwarding address
            $._holderStatus[holder].forwardPayoutTo = address(0);

            HolderStatus storage forwardedHolder = $._holderStatus[
                forwardedAddress
            ];
            uint256 len = forwardedHolder.forwardedPayouts.length;
            if (len > 1) {
                for (uint256 i = 0; i < len; ++i) {
                    if (forwardedHolder.forwardedPayouts[i] == holder) {
                        forwardedHolder.forwardedPayouts[i] = forwardedHolder
                            .forwardedPayouts[len - 1];
                        break;
                    }
                }
            }
            forwardedHolder.forwardedPayouts.pop();

            if (balanceOf(holder) == 0 && holderPayout == 0) {
                deleteUser($, $._holderStatus[holder], holder);
            }
            if (
                balanceOf(forwardedAddress) == 0 &&
                payoutBalance(forwardedAddress) == 0
            ) deleteUser($, forwardedHolder, forwardedAddress);
        }
    }

    /**
     * @notice Used to set new value for the fixed payout fee.
     * @dev Restricted to authorized accounts
     * @param newFee The new value for the fixed payout fee, in USD, 6 decimals.
     */
    function setPayoutFee(uint32 newFee) external restricted {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        $._payoutFee = newFee;
        emit PayoutFeeUpdated(newFee);
    }

    /**
     * @notice Updates the stablecoin used for payouts.
     * @dev Restricted to authorized accounts
     * @param stablecoin The address of the new stablecoin contract.
     */
    function changeStablecoin(address stablecoin) external restricted {
        if (stablecoin == address(0)) revert InvalidAddress();
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        $._stablecoin = IERC20(stablecoin);
        emit StablecoinChanged(stablecoin);
    }

    /**
     * @notice Updates the withdrawal wallet address.
     * @dev Restricted to authorized accounts
     * @param wallet The address of the new withdrawal wallet.
     */
    function changeWallet(address wallet) external restricted {
        if (wallet == address(0)) revert InvalidAddress();
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        $._wallet = wallet;
    }

    /**
     * @notice Freezes a holder if they are not already frozen.
     * @dev Restricted to authorized accounts
     * @param holder The address of the token holder to be frozen.
     */
    function freezeHolder(address holder) external restricted {
        if (holder == address(0)) revert InvalidAddress();
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        if (!$._holderStatus[holder].isFrozen) {
            $._holderStatus[holder].isFrozen = true;
            $._holderStatus[holder].frozenIndex = $._currentPayoutIndex;
            $._holderStatus[holder].frozenTimestamp = SafeCast.toUint32(
                block.timestamp
            );
            emit HolderFrozen(holder);
        }
    }

    /**
     * @notice Unfreezes a token holder and their payout balance.
     * @dev Restricted to authorized accounts
     * @param holder The address of the token holder to be unfrozen.
     */
    function unFreezeHolder(address holder) external restricted {
        if (holder == address(0)) revert InvalidAddress();
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        if ($._holderStatus[holder].isFrozen) {
            $._holderStatus[holder].isFrozen = false;
            emit HolderUnfrozen(holder);
        }
    }

    /**
     * @notice Used when holder has signed token terms and conditions
     * @param holder The address of the holder
     */
    function signTC(address holder) external restricted {
        if (holder == address(0)) revert InvalidAddress();
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        if (!$._holderStatus[holder].signedTC) {
            $._holderStatus[holder].signedTC = true;
            emit SignedTermsAndConditions(holder);
        }
    }

    /**
     * @notice Distributes payouts to users for current index.
     * @dev Restricted to authorized accounts
     * @param payoutAmount The value to distribute among token holders. In stablecoin USD, 6 decimals.
     */
    function distributePayout(uint128 payoutAmount) external restricted {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        $._payouts[$._currentPayoutIndex++] = PayoutInfo({
            amount: payoutAmount,
            totalSupply: SafeCast.toUint128(totalSupply())
        });
        emit PayoutDistributed(payoutAmount);
    }

    /**
     * @notice Allows a holder to claim their payouts.
     * @dev Deducts the fee and transfers the payout via stablecoin or an alternative mechanism.
     * Internal function, to be called within an external wrapper.
     * Function calling it needs reentrancy guard.
     * @param holder The address of the holder attempting to claim payout.
     * @param useStablecoin A value indicating whether to use stablecoin for the payout.
     * @param useCustomFee A value indiciating whetehr to use a custom fee or not.
     * @param feeValue The custom fee value to use if useCustomFee is true.
     */
    function _claimPayout(
        address holder,
        bool useStablecoin,
        bool useCustomFee,
        uint256 feeValue // AUDIT: doesn't need to be this big, would it be worth making it smaller? to uint32
    ) internal {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        uint256 payoutAmount = payoutBalance(holder);

        if (payoutAmount == 0) revert NoPayoutToClaim(holder);

        HolderStatus storage holderStatus = $._holderStatus[holder];
        if (balanceOf(holder) == 0) {
            deleteUser($, holderStatus, holder);
        } else {
            // else, update their data reflecting the recent claim
            holderStatus.lastPayoutIndexCalculated = holderStatus.isFrozen
                ? holderStatus.frozenIndex
                : $._currentPayoutIndex;
            holderStatus.isCalculated = false;
            holderStatus.calculatedPayout = 0;
        }

        //update the fee depending on the inputs
        payoutAmount -= useCustomFee ? feeValue : $._payoutFee;

        if (useStablecoin) {
            //If the user decides to be paid out in the stable coin
            IERC20 stablecoin = $._stablecoin;
            uint256 stablecoinBalance = stablecoin.balanceOf(address(this));

            uint8 numDecimals = stablecoin.decimals();
            if (numDecimals != 6) {
                payoutAmount *= 10 ** (numDecimals - 6);
            }

            if (payoutAmount > stablecoinBalance) {
                revert InsufficentStablecoinBalance();
            }

            stablecoin.transfer(holder, payoutAmount);
        }

        emit PayoutClaimed(holder, payoutAmount);
    }

    /**
     * @notice Withdraws from the stablecoin balance of the contract to the withdrawal wallet.
     * @param claimAll A boolean value indicating whether or not to claim full balance of the contract.
     * @param value The amount to claim from the contract balance if claimAll is false.
     */
    function withdraw(
        bool claimAll,
        uint256 value
    ) external restricted nonReentrant {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        IERC20 stablecoin = $._stablecoin;
        uint256 stablecoinBalance = stablecoin.balanceOf(address(this));
        uint256 valueToClaim = claimAll ? stablecoinBalance : value;

        if (valueToClaim > stablecoinBalance) {
            revert InsufficentStablecoinBalance();
        }

        stablecoin.transfer($._wallet, valueToClaim);
    }

    /**
     * @notice Returns frozen status of a token holder.
     * @param holder The address of the token holder.
     */
    function isHolderFrozen(address holder) public view returns (bool) {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        return $._holderStatus[holder].isFrozen;
    }

    /**
     * @notice Returns signed status of an address
     * @param holder The address to check status of.
     */
    function hasSignedTC(address holder) public view returns (bool) {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        return $._holderStatus[holder].signedTC;
    }

    /**
     * @notice Retrieves the payout balance of a specified holder.
     * @param holder The address of the holder.
     */
    function payoutBalance(address holder) public returns (uint256) {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        HolderStatus memory rHolderStatus = $._holderStatus[holder];
        uint8 currentPayoutIndex = $._currentPayoutIndex;

        if (
            (!rHolderStatus.isHolder) || //non-holder calling the function
            (rHolderStatus.isFrozen && rHolderStatus.frozenIndex == 0) || //user has been frozen from the start, thus no payout
            rHolderStatus.lastPayoutIndexCalculated == currentPayoutIndex // user has already been paid out up to current payout index
        ) return 0;

        if (
            // User has a previously calculated value to return
            rHolderStatus.isCalculated &&
            rHolderStatus.lastPayoutIndexCalculated == currentPayoutIndex - 1
        ) return rHolderStatus.calculatedPayout;

        //runs payoutBalance on the addresses that are forwarding payouts to this address
        for (uint256 i = 0; i < rHolderStatus.forwardedPayouts.length; ++i) {
            payoutBalance(rHolderStatus.forwardedPayouts[i]);
        }

        uint256 payoutAmount;
        uint8 payRangeStart = rHolderStatus.isFrozen
            ? rHolderStatus.frozenIndex - 1
            : currentPayoutIndex - 1;
        uint8 payRangeEnd = rHolderStatus.isCalculated
            ? rHolderStatus.lastPayoutIndexCalculated + 1
            : rHolderStatus.lastPayoutIndexCalculated;

        uint8 balanceHistoryIndex = rHolderStatus.mostRecentEntry;
        TokenBalanceChange memory curEntry = $._balanceHistory[holder][
            balanceHistoryIndex
        ];
        for (uint256 i = payRangeStart; i >= payRangeEnd; --i) {
            // iterates through the payout mapping from payRangeStart down to the payRangeEnd
            while (
                // ensures the current balance history entry is the correct one and is valid
                balanceHistoryIndex > 0 &&
                (!curEntry.isValid || balanceHistoryIndex > i)
            ) curEntry = $._balanceHistory[holder][--balanceHistoryIndex];

            PayoutInfo memory pInfo = $._payouts[i];
            payoutAmount +=
                (curEntry.tokenBalance * pInfo.amount) /
                pInfo.totalSupply;
            if (i == 0) break; // to prevent potential overflow
        }

        //update values
        HolderStatus storage holderStatus = $._holderStatus[holder];
        holderStatus.isCalculated = true;
        holderStatus.lastPayoutIndexCalculated = payRangeStart;

        //add current payout to calculated payout, or forward it to specified address
        address payoutForwardAddr = holderStatus.forwardPayoutTo;
        if (payoutForwardAddr == address(0)) {
            holderStatus.calculatedPayout += payoutAmount;
        } else {
            $._holderStatus[payoutForwardAddr].calculatedPayout += payoutAmount;
        }
        return holderStatus.calculatedPayout;
    }

    /**
     * @notice Updates the holders data upon token balance update.
     * @dev Internal function to dynamically maintain the holders.
     * @param from The address of the holder sending the tokens.
     * @param to The address of the holder recieving the tokens.
     */
    function _updateHolders(address from, address to) internal {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        uint8 payoutIndex = $._currentPayoutIndex;

        if (to != address(0)) {
            // add/update holder
            uint256 toBalance = balanceOf(to);
            HolderStatus storage tHolderStatus = $._holderStatus[to];
            if (!tHolderStatus.isHolder) {
                tHolderStatus.isHolder = true;
                tHolderStatus.lastPayoutIndexCalculated = payoutIndex;
            }
            TokenBalanceChange storage currentIndexEntry = $._balanceHistory[
                to
            ][payoutIndex];
            if (currentIndexEntry.isValid) {
                // if the holder already has an entry for this payoutIndex, update it
                currentIndexEntry.tokenBalance = toBalance;
            } else {
                // else update status data and create new entry
                tHolderStatus.mostRecentEntry = payoutIndex;
                $._balanceHistory[to][payoutIndex] = TokenBalanceChange({
                    isValid: true,
                    tokenBalance: toBalance
                });
            }
        }

        if (from != address(0)) {
            // remove/update holder
            uint256 fromBalance = balanceOf(from);
            HolderStatus storage fromHolderStatus = $._holderStatus[from];
            if (fromBalance == 0 && payoutBalance(from) == 0) {
                deleteUser($, fromHolderStatus, from);
                return;
            }
            if (fromHolderStatus.mostRecentEntry == payoutIndex) {
                // user already has an entry at the current payout index
                $._balanceHistory[from][payoutIndex].tokenBalance = fromBalance;
            } else {
                // else, create new entry
                fromHolderStatus.mostRecentEntry = payoutIndex;
                $._balanceHistory[from][payoutIndex] = TokenBalanceChange({
                    isValid: true,
                    tokenBalance: fromBalance
                });
            }
        }
    }

    /**
     * @dev Internal function to retrieve the PayOut storage struct.
     * @return $ The storage reference for PayOutStorage.
     */
    function _getHolderManagementStorage()
        internal
        pure
        returns (HolderManagementStorage storage $)
    {
        assembly {
            $.slot := HolderManagementStorageLocation
        }
    }

    /**
     * @dev Private function that deletes the data of a user when it is no longer needed.
     * @param $ Storage variable, sent in so that the holder can be fully deleted.
     * @param holderStatus The holder's HolderStatus struct.
     * @param holder The address of the holder to be deleted.
     */
    function deleteUser(
        HolderManagementStorage storage $,
        HolderStatus storage holderStatus,
        address holder
    ) private {
        bool signed = (holderStatus.isFrozen) ? false : holderStatus.signedTC;

        if (
            holderStatus.forwardPayoutTo != address(0) ||
            holderStatus.forwardedPayouts.length != 0
        ) {
            holderStatus.isFrozen = false;
            holderStatus.isCalculated = false;
            holderStatus.isHolder = false;
            holderStatus.frozenIndex = 0;
            holderStatus.lastPayoutIndexCalculated = 0;
            holderStatus.mostRecentEntry = 0;
            holderStatus.frozenTimestamp = 0;
            holderStatus.calculatedPayout = 0;
        } else {
            delete $._holderStatus[holder];
        }
        holderStatus.signedTC = signed;
    }
}
