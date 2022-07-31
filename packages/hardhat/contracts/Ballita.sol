pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol

contract Ballita is ERC1155, Ownable {

  event SetPrice(address owner, uint newPrice);
  event SetCharity(address owner, address charity);
  event SetCharityPercent(address owner, uint percent);
  event SetEpochLength(address owner, uint lengthInSeconds);
  event AdvanceEpoch(address caller, uint previousEpoch, uint winningNumber, uint newEpoch);

  uint public price;
  address payable public charity;
  uint public charityPercent;
  uint public epochLength;
  uint public currentEpoch;
  uint public topNumber = 100;
  uint public unclaimedPrizes;

  struct Winnings {
    uint winningNumber;
    uint numberOfWinners;
    uint prize;
  }

  mapping (uint => mapping (uint => uint)) public bets;
  mapping (uint => Winnings) public winnings;

  constructor(string memory uri_, uint price_, address payable charity_, uint epochLength_, uint charityPercent_) ERC1155(uri_) {
    price = price_;
    charity = charity_;
    charityPercent = charityPercent_;
    epochLength = epochLength_;
    currentEpoch = block.timestamp + epochLength;

    emit SetPrice(msg.sender, price);
    emit SetCharity(msg.sender, charity);
    emit SetCharityPercent(msg.sender, charityPercent);
    emit SetEpochLength(msg.sender, epochLength);

    // what should we do on deploy?
  }

  function setPrice(uint _newPrice) public onlyOwner {
    price = _newPrice;
    console.log(msg.sender, "set price to ", price);
    emit SetPrice(msg.sender, price);
  }

  function setCharity(address payable _newCharity) public onlyOwner {
    charity = _newCharity;
    console.log(msg.sender, "set charity to ", charity);
    emit SetCharity(msg.sender, charity);
  }

  function setEpochLength(uint _newEpochLength) public onlyOwner {
    epochLength = _newEpochLength;
    console.log(msg.sender, "set epoch length to ", epochLength);
    emit SetEpochLength(msg.sender, epochLength);
  }

  function setCharityPercent(uint _newCharityPercent) public onlyOwner {
    require(_newCharityPercent <= 100, "100% max");
    charityPercent = _newCharityPercent;
    console.log(msg.sender, "set charity % to ", charityPercent);
    emit SetCharityPercent(msg.sender, charityPercent);
  }

  function advanceEpoch() public {
    require(block.timestamp > currentEpoch, "epoch not finished");
    uint pot = address(this).balance - unclaimedPrizes;
    uint previousEpoch = currentEpoch;
    if(pot >= price) {
      uint charityPayment = ((pot * charityPercent) / 100);
      pot = pot - charityPayment;

      Winnings storage w = winnings[currentEpoch];
      w.winningNumber = 69; //TODO: chainlink vrf here
      w.numberOfWinners = bets[currentEpoch][w.winningNumber];
      if(w.numberOfWinners != 0){
        w.prize = (pot / w.numberOfWinners) - 1; //the -1 is for rounding errors
        unclaimedPrizes += pot;
      }

      charity.transfer(charityPayment);
    }

    currentEpoch = block.timestamp + epochLength;
    emit AdvanceEpoch(msg.sender, previousEpoch, winnings[previousEpoch].winningNumber, currentEpoch);
  }

  function mint(uint _betNumber) public payable {
    require(msg.value >= price, "not enough funds");
    require(block.timestamp < currentEpoch, "advance epoch to enable");
    require(_betNumber <= topNumber && _betNumber > 0, "bet number out of range");
    if(_betNumber == topNumber) _betNumber = 0;
    bets[currentEpoch][_betNumber]++;
    uint id = currentEpoch * 10000 + _betNumber;
    uint amount = msg.value/price;
    _mint(msg.sender, id, amount, msg.data);
  }

  function claim(uint _epoch, uint _qty) public {
    uint winningTicket = (_epoch * 10000) + winnings[_epoch].winningNumber;
    require(balanceOf(msg.sender, winningTicket) >= _qty, "dont have the tickets");
    _burn(msg.sender, winningTicket, _qty);
    uint claimAmount = winnings[_epoch].prize * _qty;
    unclaimedPrizes -= claimAmount;
    payable(msg.sender).transfer(claimAmount);
  }

  // to support receiving ETH by default
  receive() external payable {}
  fallback() external payable {}
}
