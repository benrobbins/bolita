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
  event SetEpochLength(address owner, uint lengthInSeconds);
  event SetTopNumber(address owner, uint topNumber);
  event AdvanceEpoch(address caller, uint newEpoch);

  uint public price;
  address public charity;
  uint public epochLength;
  uint public currentEpoch;
  uint public topNumber;

  constructor(string memory uri_, uint price_, address charity_, uint epochLength_, uint topNumber_) ERC1155(uri_) {
    price = price_;
    charity = charity_;
    epochLength = epochLength_;
    currentEpoch = block.timestamp + epochLength;
    topNumber = topNumber_;

    emit SetPrice(msg.sender, price);
    emit SetCharity(msg.sender, charity);
    emit SetEpochLength(msg.sender, epochLength);
    emit SetTopNumber(msg.sender, topNumber);
    // what should we do on deploy?
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

  function setEpochLength(uint _newEpochLength) public onlyOwner {
    epochLength = _newEpochLength;
    console.log(msg.sender, "set epoch length to ", epochLength);
    emit SetEpochLength(msg.sender, epochLength);
  }

  function setTopNumber(uint _newTopNumber) public onlyOwner {
    require(_newTopNumber <= 10000, "10000 max");
    topNumber = _newTopNumber;
    console.log(msg.sender, "set top number to ", topNumber);
    emit SetTopNumber(msg.sender, topNumber);
  }

  function advanceEpoch() public {
    require(block.timestamp > currentEpoch, "epoch not finished");
    //some stuff here
    //pay charity
    //determine winner(s)
    //set aside winnings for winners
    currentEpoch = block.timestamp + epochLength;
    emit AdvanceEpoch(msg.sender, currentEpoch);
  }

  function mint(uint _betNumber) public payable {
    require(msg.value >= price, "not enough funds");
    require(block.timestamp < currentEpoch, "advance epoch to enable");
    require(_betNumber <= topNumber && _betNumber > 0, "bet number out of range");
    if(_betNumber == topNumber) _betNumber = 0;
    uint id = currentEpoch * 10000 + _betNumber;
    uint amount = msg.value/price;
    _mint(msg.sender, id, amount, msg.data);
  }

  // to support receiving ETH by default
  receive() external payable {}
  fallback() external payable {}
}
