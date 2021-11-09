// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract TokenVesting {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable beneficiary;
    uint public nextReleaseTime;
    uint public immutable amount;
    uint public immutable duration = 30 days;

    constructor (IERC20 _token, address _beneficiary, uint _firstReleaseTime, uint _amount) public {
        require(_firstReleaseTime > block.timestamp, "TokenVesting: the first release time cannot be before current time");
        token = _token;
        beneficiary = _beneficiary;
        nextReleaseTime = _firstReleaseTime;
        amount = _amount;
    }
    
    function release() public virtual {
        require(block.timestamp >= nextReleaseTime, "release: not now");

        uint balance = token.balanceOf(address(this));
        require(amount <= balance, "release: not enough tokens to release");
        nextReleaseTime = nextReleaseTime.add(duration);
        token.safeTransfer(beneficiary, amount);
    }
}