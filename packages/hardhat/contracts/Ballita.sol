pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import 'base64-sol/base64.sol';

import './ToColor.sol';

contract Ballita is ERC1155, Ownable, VRFConsumerBaseV2 {
  VRFCoordinatorV2Interface COORDINATOR;

  using Strings for uint256;
  using ToColor for bytes3;

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
  uint public lastWinningNumber;
  uint64 private s_subscriptionId;
  bool public anyLiveBets;
  bool public waitingForOracle;

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
    uint prize;
  }

  mapping (uint => mapping (uint => uint)) public bets; //epoch=>number=>number of bets
  mapping (uint => Winnings) public winnings;
  mapping (uint256 => bytes3) public color;
  mapping (uint256 => uint256) public chubbiness;

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
    uint numberOfWinners = bets[previousEpoch][w.winningNumber];
    uint pot = address(this).balance - unclaimedPrizes;
    if(numberOfWinners != 0){
      uint charityPayment = ((pot * charityPercent) / 100);
      pot = pot - charityPayment;
      w.prize = (pot / numberOfWinners) - 1; //the -1 is for rounding errors
      unclaimedPrizes += pot;
      //charity only gets paid if there is a winner
      charity.transfer(charityPayment);
    }
    waitingForOracle = false;
  }

  function advanceEpoch() public {
    require(block.timestamp > currentEpoch, "epoch not finished");
    require(!waitingForOracle, "waiting for oracle");
    if(anyLiveBets) {
      _requestRandomWords();
      previousEpoch = currentEpoch;
      anyLiveBets = false;
      lastWinningNumber = 0;
    }
    waitingForOracle = true;
    currentEpoch = block.timestamp + epochLength;
    emit AdvanceEpoch(msg.sender, previousEpoch, currentEpoch);
  }

  //having difficulty with "stuck" oracle requests - hopfully this is not needed in production version

  function reroll() public onlyOwner {
    require(waitingForOracle && block.timestamp > currentEpoch, "no cheating");
    _requestRandomWords();
  }


  function mint(uint _betNumber) public payable returns (uint){
    require(msg.value >= price, "not enough funds");
    require(block.timestamp < currentEpoch, "advance epoch to enable");
    require(_betNumber <= topNumber && _betNumber > 0, "bet number out of range");
    bets[currentEpoch][_betNumber]++;
    uint id = currentEpoch * 10000 + _betNumber;
    uint amount = msg.value/price;
    _mint(msg.sender, id, amount, msg.data);
    anyLiveBets = true;

    bytes32 predictableRandom = keccak256(abi.encodePacked( id ));
    color[id] = bytes2(predictableRandom[0]) | ( bytes2(predictableRandom[1]) >> 8 ) | ( bytes3(predictableRandom[2]) >> 16 );
    chubbiness[id] = 35+((55*uint256(uint8(predictableRandom[3])))/255);

    return id;
  }

  function tokenURI(uint256 id) public view returns (string memory) {
      uint epochFromId = id / 10000;
      uint numberFromId = id - (epochFromId * 10000);
      console.log("token info", id, epochFromId, numberFromId);
      require(bets[epochFromId][numberFromId] > 0, "not exist");
      string memory name = string(abi.encodePacked('Ball #',id.toString()));
      string memory description = string(abi.encodePacked('This Ball is the color #',color[id].toColor(),' with a chubbiness of ',uint2str(chubbiness[id]),'!!!'));
      string memory image = Base64.encode(bytes(generateSVGofTokenById(id)));

      return
          string(
              abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    bytes(
                          abi.encodePacked(
                              '{"name":"',
                              name,
                              '", "description":"',
                              description,
                              '", "external_url":"https://burnyboys.com/token/',
                              id.toString(),
                              '", "attributes": [{"trait_type": "color", "value": "#',
                              color[id].toColor(),
                              '"},{"trait_type": "chubbiness", "value": ',
                              uint2str(chubbiness[id]),
                              '}], "image": "',
                              'data:image/svg+xml;base64,',
                              image,
                              '"}'
                          )
                        )
                    )
              )
          );
  }

  function generateSVGofTokenById(uint256 id) internal view returns (string memory) {

    string memory svg = string(abi.encodePacked(
      '<svg width="400" height="400" xmlns="http://www.w3.org/2000/svg">',
        renderTokenById(id),
      '</svg>'
    ));

    return svg;
  }


  // Visibility is `public` to enable it being called by other contracts for composition.
  function renderTokenById(uint256 id) public view returns (string memory) {

    string memory render = string(abi.encodePacked(
      '<g id="eye1">',
          '<ellipse stroke-width="3" ry="29.5" rx="29.5" id="svg_1" cy="154.5" cx="181.5" stroke="#000" fill="#fff"/>',
          '<ellipse ry="3.5" rx="2.5" id="svg_3" cy="154.5" cx="173.5" stroke-width="3" stroke="#000" fill="#000000"/>',
        '</g>',
        '<g id="head">',
          '<ellipse fill="#',
          color[id].toColor(),
          '" stroke-width="3" cx="204.5" cy="211.80065" id="svg_5" rx="',
          chubbiness[id].toString(),
          '" ry="51.80065" stroke="#000"/>',
          '<text font-size="30" font-weight="bold" x="180" y="240" fill="red" stroke="#000" stroke-width="1" font-family="sans-serif">',
          chubbiness[id].toString(),
          '</text>',
        '</g>',
        '<g id="eye2">',
          '<ellipse stroke-width="3" ry="29.5" rx="29.5" id="svg_2" cy="168.5" cx="209.5" stroke="#000" fill="#fff"/>',
          '<ellipse ry="3.5" rx="3" id="svg_4" cy="169.5" cx="208" stroke-width="3" fill="#000000" stroke="#000"/>',
        '</g>'
      ));

    return render;
  }

  function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
      if (_i == 0) {
          return "0";
      }
      uint j = _i;
      uint len;
      while (j != 0) {
          len++;
          j /= 10;
      }
      bytes memory bstr = new bytes(len);
      uint k = len;
      while (_i != 0) {
          k = k-1;
          uint8 temp = (48 + uint8(_i - _i / 10 * 10));
          bytes1 b1 = bytes1(temp);
          bstr[k] = b1;
          _i /= 10;
      }
      return string(bstr);
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
