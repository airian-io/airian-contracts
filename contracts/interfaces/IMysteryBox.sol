// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMysteryBox {
    function claimByStaking(address to, uint256 amount) external;

    function claimKeys(address to, uint256 amount) external;
}
