pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Ballita is ERC1155, Ownable, VRFConsumerBaseV2 {
  VRFCoordinatorV2Interface COORDINATOR;

  event SetPrice(address owner, uint newPrice);
  event SetCharity(address owner, address charity);
  event SetCharityPercent(address owner, uint percent);
  event SetEpochLength(address owner, uint lengthInSeconds);
  event AdvanceEpoch(address caller, uint previousEpoch, uint newEpoch);

  uint public price;
  address payable public charity;
  uint public charityPercent;
  uint public epochLength;
  uint public currentEpoch;
  uint public previousEpoch;
  uint public topNumber = 10;
  uint public unclaimedPrizes;
  uint64 private s_subscriptionId;
  bool public anyLiveBets;
  uint public lastWinningNumber;

  // Rinkeby coordinator. For other networks,
  // see https://docs.chain.link/docs/vrf-contracts/#configurations
  address vrfCoordinator = 0x6168499c0cFfCaCD319c818142124B7A15E857ab;

  // The gas lane to use, which specifies the maximum gas price to bump to.
  // For a list of available gas lanes on each network,
  // see https://docs.chain.link/docs/vrf-contracts/#configurations
  bytes32 keyHash = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;

  // Depends on the number of requested values that you want sent to the
  // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
  // so 100,000 is a safe default for this example contract. Test and adjust
  // this limit based on the network that you select, the size of the request,
  // and the processing of the callback request in the fulfillRandomWords()
  // function.
  uint32 callbackGasLimit = 500000;

  // The default is 3, but you can set this higher.
  uint16 requestConfirmations = 3;

  uint32 numWords =  1;

  uint256 public s_requestId;




  struct Winnings {
    uint winningNumber;
    uint numberOfWinners;
    uint prize;
  }

  mapping (uint => mapping (uint => uint)) public bets;
  mapping (uint => Winnings) public winnings;

  constructor(string memory uri_, uint price_, address payable charity_, uint epochLength_, uint charityPercent_, uint64 subscriptionId_) ERC1155(uri_) VRFConsumerBaseV2(vrfCoordinator){
    price = price_;
    charity = charity_;
    charityPercent = charityPercent_;
    epochLength = epochLength_;
    currentEpoch = block.timestamp + epochLength;

    COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
    s_subscriptionId = subscriptionId_;

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

  // Assumes the subscription is funded sufficiently.
  function _requestRandomWords() internal {
    // Will revert if subscription is not set and funded.
    s_requestId = COORDINATOR.requestRandomWords(
      keyHash,
      s_subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      numWords
    );
  }

  function fulfillRandomWords(
    uint256, /* requestId */
    uint256[] memory randomWords
  ) internal override {
    lastWinningNumber = randomWords[0] % topNumber +1;
    Winnings storage w = winnings[previousEpoch];
    w.winningNumber = lastWinningNumber;
    w.numberOfWinners = bets[previousEpoch][w.winningNumber];
    uint pot = address(this).balance - unclaimedPrizes;
    if(w.numberOfWinners != 0){
      uint charityPayment = ((pot * charityPercent) / 100);
      pot = pot - charityPayment;
      w.prize = (pot / w.numberOfWinners) - 1; //the -1 is for rounding errors
      unclaimedPrizes += pot;
      //charity only gets paid if there is a winner
      charity.transfer(charityPayment);
    }
  }

  function advanceEpoch() public {
    require(block.timestamp > currentEpoch, "epoch not finished");
    require(winnings[previousEpoch].winningNumber != 0 || previousEpoch == 0, "waiting for oracle");
    if(anyLiveBets) {
      _requestRandomWords();
      previousEpoch = currentEpoch;
      anyLiveBets = false;
      lastWinningNumber = 0;
    }

    currentEpoch = block.timestamp + epochLength;
    emit AdvanceEpoch(msg.sender, previousEpoch, currentEpoch);
  }

  //having difficulty with "stuck" oracle requests - hopfully this is not needed in production version

  function reroll() public onlyOwner {
    require(winnings[previousEpoch].winningNumber == 0, "no cheating");
    _requestRandomWords();
  }
  

  function mint(uint _betNumber) public payable {
    require(msg.value >= price, "not enough funds");
    require(block.timestamp < currentEpoch, "advance epoch to enable");
    require(_betNumber <= topNumber && _betNumber > 0, "bet number out of range");
    bets[currentEpoch][_betNumber]++;
    uint id = currentEpoch * 10000 + _betNumber;
    uint amount = msg.value/price;
    _mint(msg.sender, id, amount, msg.data);
    anyLiveBets = true;
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
