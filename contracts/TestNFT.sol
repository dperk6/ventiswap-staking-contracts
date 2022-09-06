// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TestNFT is ERC721 {
    uint256 private _count;

    constructor() ERC721("TEST NFT", "TNFT") {
        _mint(msg.sender, 1);
        _mint(msg.sender, 2);
        _mint(msg.sender, 3);
        _mint(msg.sender, 4);

        _count += 4;
    }

    function mint() external
    {
        _mint(msg.sender, _count + 1);
        _count += 1;
    }
}