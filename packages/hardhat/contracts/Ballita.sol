pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol

contract Ballita is ERC1155, Ownable {

  event SetPurpose(address sender, string purpose);
  event SetPrice(address owner, uint newPrice);
  event SetCharity(address owner, address charity);

  string public purpose = "building ballita";

  uint public price;
  address public charity;

  constructor(string memory uri_, uint price_, address charity_) ERC1155(uri_) {
    price = price_;
    charity = charity_;
    // what should we do on deploy?
  }

  function setPurpose(string memory newPurpose) public {
      purpose = newPurpose;
      console.log(msg.sender,"set purpose to",purpose);
      emit SetPurpose(msg.sender, purpose);
  }

  function setPrice(uint _newPrice) public onlyOwner {
    price = _newPrice;
    console.log(msg.sender, "set price to ", price);
    emit SetPrice(msg.sender, price);
  }

  function setCharity(address _newCharity) public onlyOwner {
    charity = _newCharity;
    console.log(msg.sender, "set charity to ", charity);
    emit SetCharity(msg.sender, charity);
  }

  // to support receiving ETH by default
  receive() external payable {}
  fallback() external payable {}
}
