// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {VennFirewallConsumer} from "@ironblocks/firewall-consumer/contracts/consumers/VennFirewallConsumer.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LoyaltyPointsMarketSafe is VennFirewallConsumer, Ownable {

    event PointsPurchased(address indexed buyer, uint256 indexed tokenId, uint256 amountWei, uint256 weiPerPoint);
    event BoostToTop(address indexed buyer, uint256 indexed tokenId, uint256 amountWei);

    uint256 public weiPerPoint;
    uint256 public boostPaymentAmount;

    error InvalidAmount();

    constructor(uint256 _weiPerPoint) {
        weiPerPoint = _weiPerPoint;
    }

    function purchasePoints(uint256 tokenId) external payable firewallProtected {
        emit PointsPurchased(msg.sender, tokenId, msg.value, weiPerPoint);
    }

    function boostToTop(uint256 tokenId) external payable firewallProtected {
        if (msg.value != boostPaymentAmount) revert InvalidAmount();
        emit BoostToTop(msg.sender, tokenId, msg.value);
    }

    //-----------------------------------------------------------------------------
    //-------------------------------  Admin  -------------------------------------
    //-----------------------------------------------------------------------------

    function withdrawFunds(address payable _to) external onlyOwner firewallProtected {
        _to.transfer(address(this).balance);
    }

    function setWeiPerPoint(uint256 _weiPerPoint) external onlyOwner firewallProtected {
        weiPerPoint = _weiPerPoint;
    }

    function setBoostPaymentAmount(uint256 _boostPaymentAmount) external onlyOwner firewallProtected {
        boostPaymentAmount = _boostPaymentAmount;
    }
}
