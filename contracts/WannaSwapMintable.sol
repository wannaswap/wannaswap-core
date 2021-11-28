// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/GSN/Context.sol";

contract WannaSwapMintable is Context, Ownable {
    mapping(address => bool) public _minters;
    uint public minterLength;

    event AddMinter(address indexed user);
    event RemoveMinter(address indexed user);

    constructor () internal {
        address msgSender = _msgSender();
        _minters[msgSender] = true;
        minterLength = 1;

        emit AddMinter(msgSender);
    }

    modifier onlyMinter() {
        require(_minters[_msgSender()], "WannaSwapMintable: MUST BE MINTER");
        _;
    }

    function addMinter(address _user) external virtual onlyOwner {
        require(!_minters[_user], "addMinter: MINTER HAS EXISTED");
        _minters[_user] = true;
        minterLength++;

        emit AddMinter(_user);
    }

    function removeMinter(address _user) external virtual onlyOwner {
        require(_minters[_user], "addMinter: MINTER HAS NOT EXISTED");
        _minters[_user] = false;
        minterLength--;

        emit RemoveMinter(_user);
    }
}