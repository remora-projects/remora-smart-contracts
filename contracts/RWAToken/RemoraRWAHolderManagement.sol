// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @custom:security-contact support@remora.us
/**
 * @title RemoraRWAHolderManagement
 * @notice This abstract contract facilitates payouts in stablecoins to token holders based on their balances.
 * It includes functionality for managing holders, distributing payouts, and withdrawing contract balances.
 * @dev This contract uses OpenZeppelin upgradeable utilities for modular and upgradeable design.
 */
abstract contract RemoraRWAHolderManagement is
    Initializable,
    ReentrancyGuardUpgradeable,
    ContextUpgradeable,
    AccessManagedUpgradeable,
    ERC20Upgradeable
{
    /// @dev Contains token holder's data.
    struct HolderStatus {
        bool isFrozen;
        /// @dev Whether or not their payout balance has been previously calulated.
        bool isCalculated;
        /// @dev The index in which the user has been frozen.
        uint8 frozenIndex;
        uint8 lastPayoutIndexCalculated;
        /// @dev Number of entries in balance history mapping.
        uint8 numEntries;
        /// @dev The index of the most recent entry in balance history.
        uint8 mostRecentEntry;
        /// @dev The value of the most recently calculated payout.
        uint256 calculatedPayout;
    }

    /// @dev Contains info at the time of payout distribution
    struct payoutStruct {
        uint256 amount;
        uint256 totalSupply;
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
        uint256 _payoutFee;
        /// @dev The current index that is yet to be paid out.
        uint8 _currentPayoutIndex;
        /// @dev mapping to a struct containing payout amounts and tokenSupply that the payout indices correlate to.
        mapping(uint256 => payoutStruct) _payouts;
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
    event PayoutFeeUpdated(uint256 newFee);

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
    event PayoutDistributed(uint256 totalDistributed);

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

    /// @notice Error indicating that a holder attempted to claim payout when their available balance is zero.
    error NoPayoutToClaim();

    /// @notice Error indicating that the contract has insufficient stablecoin balance for the requested operation.
    error InsufficentStablecoinBalance();

    /// @notice Error indicating that a frozen user is restricted from the requested operation.
    error UserIsFrozen();

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
        uint256 _payoutFee
    ) internal onlyInitializing {
        __AccessManaged_init(_initialAuthority);
        __ReentrancyGuard_init();
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
        uint256 _payoutFee
    ) internal onlyInitializing {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        $._stablecoin = IERC20(_stablecoin);
        $._wallet = _wallet;
        $._payoutFee = _payoutFee;
        $._currentPayoutIndex = 0;
    }

    /**
     * @notice Used to set new value for the fixed payout fee.
     * @dev Restricted to authorized accounts
     * @param newFee The new value for the fixed payout fee, in USD, 6 decimals.
     */
    function setPayoutFee(uint256 newFee) external restricted {
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
     * @notice Distributes payouts to users for current index.
     * @dev Restricted to authorized accounts
     * @param payoutAmount The value to distribute among token holders. In stablecoin USD, 6 decimals.
     */
    function distributePayout(uint256 payoutAmount) external restricted {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        $._payouts[$._currentPayoutIndex++] = payoutStruct({
            amount: payoutAmount,
            totalSupply: totalSupply()
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
        uint256 feeValue
    ) internal {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        uint256 payoutAmount = payoutBalance(holder);

        if (payoutAmount == 0) revert NoPayoutToClaim();

        if (balanceOf(holder) == 0) {
            // if user is not a holder after claiming payout, delete thier data
            deleteUserData($, holder);
        } else {
            // else, update their data reflecting the recent claim
            HolderStatus storage holderStatus = $._holderStatus[holder];
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
            uint256 stablecoinBalance = $._stablecoin.balanceOf(address(this));

            if (payoutAmount > stablecoinBalance) {
                revert InsufficentStablecoinBalance();
            }

            $._stablecoin.transfer(holder, payoutAmount);
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
        uint256 stablecoinBalance = $._stablecoin.balanceOf(address(this));
        uint256 valueToClaim = claimAll ? stablecoinBalance : value;

        if (valueToClaim > stablecoinBalance) {
            revert InsufficentStablecoinBalance();
        }

        $._stablecoin.transfer($._wallet, valueToClaim);
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
     * @notice Retrieves the payout balance of a specified holder.
     * @param holder The address of the holder.
     */
    function payoutBalance(address holder) public returns (uint256) {
        HolderManagementStorage storage $ = _getHolderManagementStorage();
        HolderStatus storage holderStatus = $._holderStatus[holder];
        uint8 currentPayoutIndex = $._currentPayoutIndex;

        if (
            (holderStatus.numEntries == 0) || //non-holder calling the function
            (holderStatus.isFrozen && holderStatus.frozenIndex == 0) || //user has been frozen from the start, thus no payout
            holderStatus.lastPayoutIndexCalculated == currentPayoutIndex // user has already been paid out up to current payout index
        ) return 0;

        if (
            // User has a previously calculated value to return
            holderStatus.isCalculated &&
            holderStatus.lastPayoutIndexCalculated == currentPayoutIndex - 1
        ) {
            return holderStatus.calculatedPayout;
        }

        uint256 payoutAmount;
        uint8 payRangeStart = holderStatus.isFrozen
            ? holderStatus.frozenIndex - 1
            : currentPayoutIndex - 1;
        uint8 payRangeEnd = holderStatus.isCalculated
            ? holderStatus.lastPayoutIndexCalculated + 1
            : holderStatus.lastPayoutIndexCalculated;

        uint8 balanceHistoryIndex = holderStatus.mostRecentEntry;
        for (uint256 i = payRangeStart; i >= payRangeEnd; --i) {
            // iterates through the payout mapping from payRangeStart down to the payRangeEnd
            while (
                // ensures the current balance history entry is the correct one and is valid
                balanceHistoryIndex > 0 &&
                (!$._balanceHistory[holder][balanceHistoryIndex].isValid ||
                    balanceHistoryIndex > i)
            ) {
                --balanceHistoryIndex;
            }
            payoutStruct memory pInfo = $._payouts[i];
            payoutAmount +=
                ($._balanceHistory[holder][balanceHistoryIndex].tokenBalance *
                    pInfo.amount) /
                pInfo.totalSupply;
            if (
                balanceHistoryIndex == i &&
                balanceHistoryIndex != holderStatus.mostRecentEntry
            ) {
                // Deletes old unneeded history entries
                delete $._balanceHistory[holder][balanceHistoryIndex];
                --holderStatus.numEntries;
            }
            if (i == 0) break; // to prevent potential overflow
        }
        holderStatus.calculatedPayout += payoutAmount;

        //update values
        holderStatus.isCalculated = true;
        holderStatus.lastPayoutIndexCalculated = payRangeStart;
        return holderStatus.calculatedPayout;
    }

    /**
     * @notice Internal function that is used to delete user data.
     * @param $ value for HolderManagementStorage.
     * @param holder The address of the holder to be removed.
     */
    function deleteUserData(
        HolderManagementStorage storage $,
        address holder
    ) internal {
        // most recent entry should be the only entry left when this is called
        delete $._balanceHistory[holder][
            $._holderStatus[holder].mostRecentEntry
        ];
        delete $._holderStatus[holder];
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
            if (tHolderStatus.numEntries == 0) {
                // if holder is a new holder
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
                ++tHolderStatus.numEntries;
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
            if (fromBalance == 0 && payoutBalance(from) == 0) {
                deleteUserData($, from);
                return;
            }
            HolderStatus storage fromHolderStatus = $._holderStatus[from];
            if (fromHolderStatus.mostRecentEntry == payoutIndex) {
                // user already has an entry at the current payout index
                $._balanceHistory[from][payoutIndex].tokenBalance = fromBalance;
            } else {
                // else, create new entry
                ++fromHolderStatus.numEntries;
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
}
