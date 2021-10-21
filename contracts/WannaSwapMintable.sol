// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/GSN/Context.sol";

contract WannaSwapMintable is Context, Ownable {
    mapping(address => bool) public _minters;

    event SetMinter(address indexed user, bool isMinter);

    constructor () internal {
        address msgSender = _msgSender();
        _minters[msgSender] = true;
        emit SetMinter(msgSender, true);
    }

    modifier onlyMinter() {
        require(_minters[_msgSender()], "WannaSwapMintable: MUST BE MINTER");
        _;
    }

    function setMinter(address _user, bool _isMinter) public virtual onlyOwner {
        emit SetMinter(_user, _isMinter);
        _minters[_user] = _isMinter;
    }

    function addMinter(address _user) public virtual onlyOwner {
        setMinter(_user, true);
    }

    function removeMinter(address _user) public virtual onlyOwner {
        setMinter(_user, false);
    }
}