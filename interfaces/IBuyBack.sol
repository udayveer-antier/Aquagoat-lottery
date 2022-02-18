//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBuyBack {
    function checkBalance() external payable returns (bytes32);
}