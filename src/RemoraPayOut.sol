// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/// @custom:security-contact support@remora.us
/**
 * @title RemoraRWAPayOut
 * @notice This abstract contract facilitates payouts in stablecoins to token holders based on their balances. 
 * It includes functionality for managing holders, distributing payouts, and withdrawing contract balances.
 * @dev This contract uses OpenZeppelin upgradeable utilities for modular and upgradeable design.
 */
abstract contract RemoraRWAPayOut is Initializable, ReentrancyGuardUpgradeable, ContextUpgradeable, PausableUpgradeable, ERC20Upgradeable {
    /// @custom:storage-location erc7201:remora.storage.PayOut
    struct PayOutStorage {
        /**
         * @notice The address of the wallet to which the contract's balance can be withdrawn.
         */
        address _wallet;

        /**
         * @notice The IERC20 stablecoin used for facilitating payouts. 
         */
        IERC20 _stablecoin; 

        /**
         * @notice The fee percentage deducted from payouts, represented with 3 decimals (e.g., 1000 = 1%, 100000 = 100%).
         */
        uint256 _feePercentage;
    
        /**
         * @notice The array of addresses representing the current token holders. Used for iterating during payouts.
         */
        address[] _holders;

        /**
         * @notice A mapping of token holder addresses to a boolean indicating whether they currently hold tokens. 
         */
        mapping(address => bool) _isHolder;

        /**
         * @notice A mapping of token holder addresses to their payout balances, denominated in USD. 
         */
        mapping(address => uint256) _rentBalance;
    }

    // keccak256(abi.encode(uint256(keccak256("remora.storage.PayOut")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PayOutStorageLocation = 0x0;

    /**
     * @dev Internal function to retrieve the PayOut storage struct.
     * @return $ The storage reference for PayOutStorage.
     */
    function _getPayOutStorage() private pure returns (PayOutStorage storage $) {
        assembly {
           $.slot := PayOutStorageLocation
        }
    }

    /**
     * @notice Event emitted when a new holder is added to the _holders array.
     * @param holder The address of the new holder.
     */
    event AddedHolder(address holder);

    /**
     * @notice Event emitted when a holder with a zero token balance is removed from the _holders array.
     * @param holder The address of the removed holder.
     */
    event RemovedHolder(address holder);

    /**
     * @notice Event emitted when a holder claims their rental payout.
     * @param holder The address of the holder.
     * @param amount The amount of rent claimed.
     */
    event RentClaimed(address holder, uint256 amount);

    /**
     * @notice Event emitted when rental payouts are distributed among token holders.
     */
    event RentDistributed();

    /**
     * @notice Error indicating that a holder attempted to claim rent when their payout balance is zero.
     * @param holder The address of the holder attempting to claim rent.
     */
    error NoRentToClaim(address holder);

    /**
     * @notice Error indicating that the contract has insufficient stablecoin balance for the requested operation.
     */
    error InsufficentStablecoinBalance();

    /**
     * @notice Error indicating that a function was called with an invalid address.
     */
    error InvalidAddress();

    /**
     * @notice Initializes the contract with the stablecoin address, withdrawal wallet address, and fee percentage.
     * @dev Should be called during deployment or upgrade to set initial state.
     * @param _stablecoin The address of the stablecoin contract.
     * @param _wallet The address of the withdrawal wallet.
     * @param _feePercentage The fee percentage (3 decimals, e.g., 1000 = 1%).
     */
    function __RemoraPayout_init(address _stablecoin, address _wallet, uint256 _feePercentage) internal onlyInitializing {
        __ReentrancyGuard_init();
        __RemoraPayout_init_unchained(_stablecoin, _wallet, _feePercentage);
    }

    /**
     * @notice Sets the stablecoin, wallet, and fee percentage in the PayOut storage during initialization.
     * @dev Part of the initialization process.
     * @param _stablecoin The address of the stablecoin contract.
     * @param _wallet The address of the withdrawal wallet.
     * @param _feePercentage The fee percentage (3 decimals, e.g., 1000 = 1%).
     */
    function __RemoraPayout_init_unchained(address _stablecoin, address _wallet, uint256 _feePercentage) internal onlyInitializing { 
        PayOutStorage storage $ = _getPayOutStorage();
        $._stablecoin = IERC20(_stablecoin);
        $._wallet = _wallet;
        $._feePercentage = _feePercentage;
    }

    /**
     * @notice Updates the stablecoin address used for payouts.
     * @dev Internal function for modifying the stablecoin address. To be used in child contract with restricted modifier.
     * @param stablecoin The address of the new stablecoin contract.
     */
    function _changeStablecoin(address stablecoin) internal virtual {
        if (stablecoin == address(0)) revert InvalidAddress();
        PayOutStorage storage $ = _getPayOutStorage();
        $._stablecoin = IERC20(stablecoin);
    }
    

    /**
     * @notice Updates the withdrawal wallet address.
     * @dev Internal function for modifying the wallet address. To be used in child contract with restricted modifier.
     * @param wallet The address of the new withdrawal wallet.
     */
    function _changeWallet(address wallet) internal virtual {
        if (wallet == address(0)) revert InvalidAddress();
        PayOutStorage storage $ = _getPayOutStorage();
        $._wallet = wallet;
    }

    /**
     * @notice Adds a new token holder to the _holders list if their balance is greater than zero.
     * @dev Internal function to update the holders list dynamically.
     * @param account The address of the token holder to be added.
     */
    function _addHolder(address account) internal virtual {
        if(account != address(0)){
            PayOutStorage storage $ = _getPayOutStorage();
            if (!$._isHolder[account] && balanceOf(account) > 0) {
                $._isHolder[account] = true;
                $._holders.push(account);
                emit AddedHolder(account);
            }
        }
    }

    /**
     * @notice Removes a token holder from the _holders list if their balance is zero.
     * @dev Internal function to dynamically maintain the holders list.
     * @param account The address of the token holder to be removed.
     */
    function _removeHolder(address account) internal virtual {
        if(account != address(0)){
            PayOutStorage storage $ = _getPayOutStorage();
            if($._isHolder[account] && balanceOf(account) == 0) {
                $._isHolder[account] = false;
                for (uint256 i = 0; i < $._holders.length; i++) {
                    if ($._holders[i] == account) {
                        $._holders[i] = $._holders[$._holders.length - 1];
                        $._holders.pop();
                        emit RemovedHolder(account);
                        break;
                    }
                }
            }
        }
    }

    /**
     * @notice Calculates and distributes rental payouts among holders based on their token balances.
     * @dev Internal function, callable by child contracts to implement restricted distribution logic.
     * @param rentAmount The total rent amount to be distributed (6 decimals).
     */
    function _distributeRentalPayments(uint256 rentAmount) internal virtual {
        PayOutStorage storage $ = _getPayOutStorage();
        uint256 totalSupply = totalSupply();
        uint256 holdersLen = $._holders.length;

        for (uint256 i = 0; i < holdersLen; i++) {
            address holder = $._holders[i];
            uint256 holderBalance = balanceOf(holder);
            if (holderBalance > 0) {
                $._rentBalance[holder] += (rentAmount * holderBalance) / totalSupply;
            }
        }

        emit RentDistributed();
    }

    /**
     * @notice Retrieves the payout balance of a specified holder.
     * @param holder The address of the holder.
     * @return The current payout balance of the holder.
     */
    function rentBalance(address holder) public virtual returns (uint256) {
        PayOutStorage storage $ = _getPayOutStorage();
        return $._rentBalance[holder];
    }


    /**
     * @notice Allows a holder to claim their rental payouts.
     * @dev Deducts the fee and transfers the payout via stablecoin or an alternative mechanism.
     * @param stablecoin A boolean indicating whether to use stablecoin for the payout.
     */
    function claimRent(bool stablecoin) external nonReentrant whenNotPaused virtual {
        PayOutStorage storage $ = _getPayOutStorage();
        address sender = _msgSender();
        uint256 rentAmount = $._rentBalance[sender];

        $._rentBalance[sender] = 0;

        if(stablecoin) {
            rentAmount -= (rentAmount * $._feePercentage) / 100000;
            uint256 stablecoinBalance = $._stablecoin.balanceOf(address(this));

            if (rentAmount == 0) { revert NoRentToClaim(sender); }
            if (rentAmount > stablecoinBalance) { revert InsufficentStablecoinBalance(); }

            $._stablecoin.transfer(sender, rentAmount);
        }

        emit RentClaimed(sender, rentAmount);
    }

    /**
     * @notice Withdraws the entire stablecoin balance of the contract to the withdrawal wallet.
     * @dev Internal function, callable by child contracts with restricted access.
     */
    function _withdraw() internal nonReentrant virtual {
        PayOutStorage storage $ = _getPayOutStorage();
        IERC20 stablecoin = $._stablecoin;
        uint256 stablecoinBalance = stablecoin.balanceOf(address(this));

        if (stablecoinBalance == 0) { revert InsufficentStablecoinBalance(); }

        stablecoin.transfer($._wallet, stablecoinBalance);
    }
}