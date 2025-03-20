// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @custom:security-contact support@remora.us
/**
 * @title RemoraRWAHolderManagement
 * @notice This abstract contract facilitates payouts in stablecoins to token holders based on their balances.
 * It includes functionality for managing holders, distributing payouts, and withdrawing contract balances.
 * @dev This contract uses OpenZeppelin upgradeable utilities for modular and upgradeable design.
 */
abstract contract RemoraRWALockUp is Initializable {
    struct Lockup {
        uint32 amount;
        uint32 time;
    }

    struct UserLockInfo {
        uint16 startInd;
        uint16 endInd;
        mapping(uint16 => Lockup) tokenLockUp;
    }

    /// @custom:storage-location erc7201:remora.storage.LockUp
    struct LockUpStorage {
        /// @dev The amount of time in seconds the token will be locked up for (maximum should be around 12 months)
        uint32 _lockUpTime;
        /// @dev Mapping of user addresses to their UserLockInfo structs
        mapping(address => UserLockInfo) _userData;
    }

    // keccak256(abi.encode(uint256(keccak256("remora.storage.LockUp")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LockUpStorageLocation =
        0x7f57b89043906059b16763d58e88153708e265ea7fb49e332213e40b96b7fb00;

    error CannotUnlockTokens();

    function __RemoraLockUp_init(uint32 lockUpTime) internal onlyInitializing {
        __RemoraLockUp_init_unchained(lockUpTime);
    }

    function __RemoraLockUp_init_unchained(
        uint32 lockUpTime
    ) internal onlyInitializing {
        _setLockUpTime(lockUpTime);
    }

    function _setLockUpTime(uint32 newLockUpTime) internal {
        LockUpStorage storage $ = _getLockUpStorage();
        $._lockUpTime = newLockUpTime;
    }

    function _lockTokens(address holder, uint256 amount) internal {
        LockUpStorage storage $ = _getLockUpStorage();

        if ($._lockUpTime == 0 || amount == 0) return;

        UserLockInfo storage userData = $._userData[holder];
        uint16 len = userData.endInd - userData.startInd;
        uint32 curTime = SafeCast.toUint32(block.timestamp);
        if (
            len > 0 &&
            curTime - userData.tokenLockUp[userData.endInd - 1].time < 1 days
        ) {
            userData.tokenLockUp[userData.endInd - 1].amount += SafeCast
                .toUint32(amount);
        } else {
            userData.tokenLockUp[userData.endInd++] = Lockup({
                amount: SafeCast.toUint32(amount),
                time: SafeCast.toUint32(block.timestamp)
            });
        }
    }

    function availableTokens(address holder) public view returns (uint tokens) {
        LockUpStorage storage $ = _getLockUpStorage();
        UserLockInfo storage userData = $._userData[holder];
        uint32 lockUpTime = $._lockUpTime;
        uint32 curTime = SafeCast.toUint32(block.timestamp);
        for (uint16 i = userData.startInd; i < userData.endInd; ++i) {
            Lockup memory curEntry = userData.tokenLockUp[i];
            if (curTime - curEntry.time >= lockUpTime) {
                tokens += curEntry.amount;
            } else {
                break;
            }
        }
    }

    // maybe add an extra bool param that can negate the time if we need to take tokens without messing up the user's token lock
    function _unlockTokens(
        address holder,
        uint256 amount,
        bool disregardTime
    ) internal {
        LockUpStorage storage $ = _getLockUpStorage();
        uint32 lockUpTime = $._lockUpTime;
        if (lockUpTime == 0 || amount == 0) return;

        uint32 curTime = SafeCast.toUint32(block.timestamp);
        UserLockInfo storage userData = $._userData[holder];

        for (uint16 i = userData.startInd; i < userData.endInd; ++i) {
            if (
                !disregardTime &&
                curTime - userData.tokenLockUp[i].time < lockUpTime
            ) break;
            uint32 curEntryAmount = userData.tokenLockUp[i].amount;

            if (curEntryAmount > amount) {
                userData.tokenLockUp[i].amount -= SafeCast.toUint32(amount);
                amount = 0;
                break;
            } else {
                ++userData.startInd;
                amount -= curEntryAmount;
                if (amount == 0) break;
            }
        }
        if (amount != 0) revert CannotUnlockTokens();
        if (userData.startInd == userData.endInd) {
            userData.startInd = 0;
            userData.endInd = 0;
        }
    }

    /**
     * @dev Internal function to retrieve the PayOut storage struct.
     * @return $ The storage reference for PayOutStorage.
     */
    function _getLockUpStorage()
        internal
        pure
        returns (LockUpStorage storage $)
    {
        assembly {
            $.slot := LockUpStorageLocation
        }
    }
}
