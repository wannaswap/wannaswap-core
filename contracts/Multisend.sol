// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Multisend is Ownable {
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    
    function release(IERC20 _token, address[] memory _users, uint[] memory _amounts) public onlyOwner {
        require(_users.length == _amounts.length, "release: BAD ARRAY");
        for (uint i = 0; i < _users.length; i++) {
            uint balance = _token.balanceOf(address(this));
            require(_amounts[i] <= balance, "release: not enough tokens to release");
            _token.safeTransfer(_users[i], _amounts[i]);
        }
    }
    
    function linearRelease(IERC20 _token, address[] memory _users, uint _amount) public onlyOwner {
        for (uint i = 0; i < _users.length; i++) {
            uint balance = _token.balanceOf(address(this));
            require(_amount <= balance, "release: not enough tokens to release");
            _token.safeTransfer(_users[i], _amount);
        }
    }
}