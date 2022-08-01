import React, { useState, useEffect } from "react";
import { Link } from "react-router-dom";
import { useContractReader } from "eth-hooks";
import { useEventListener } from "eth-hooks/events/useEventListener";
import { Button, Col, Menu, Row, InputNumber, Space, List, Card } from "antd";
import { Address, Balance } from "../components";
import { ethers } from "ethers";

/**
 * web3 props can be passed from '../App.jsx' into your local view component for use
 * @param {*} yourLocalBalance balance on current network
 * @param {*} readContracts contracts from current chain already pre-loaded using ethers contract module. More here https://docs.ethers.io/v5/api/contract/contract/
 * @returns react component
 **/
function Home({
  yourLocalBalance,
  readContracts,
  tx,
  writeContracts,
  address,
  mainnetProvider,
  blockExplorer,
  localProvider,
  price,
 }) {

  // you can also use hooks locally in your component of choice
  // in this case, let's keep track of 'purpose' variable from our contract
  const currentEpoch = useContractReader(readContracts, "Ballita", "currentEpoch");
  console.log("currentEpoch", currentEpoch);
  const previousEpoch = useContractReader(readContracts, "Ballita", "previousEpoch");

  const betPrice = useContractReader(readContracts, "Ballita", "price");
  const topNumber = useContractReader(readContracts, "Ballita", "topNumber");
  const charity = useContractReader(readContracts, "Ballita", "charity");
  const charityPercent = useContractReader(readContracts, "Ballita", "charityPercent");
  const dateTime = Date.now();
  const timestamp = Math.floor(dateTime / 1000);

  const advanceEvents = useEventListener(readContracts, "Ballita", "AdvanceEpoch", localProvider, 1);
  console.log("📟 advance epoch events:", advanceEvents, advanceEvents.length);

  const currentEpochFormatted = currentEpoch&&currentEpoch.toNumber();
  const topNumberFormatted = topNumber&&topNumber.toNumber();

  const [buying, setBuying] = useState();
  const [claiming, setClaiming] = useState();
  const [betNumber, setBetNumber] = useState("1");

  var countdown = currentEpochFormatted - timestamp > 0 ? currentEpochFormatted - timestamp : 0;
  var nextDrawing = countdown <= 0 ? "Now!" : Date(currentEpochFormatted*1000);

  const [yourCollectibles, setYourCollectibles] = useState([]);

  useEffect(() => {
    const updateYourCollectibles = async () => {
      const collectibleUpdate = [];

      for (let bet = 0; bet < topNumber; bet++) {
        const tokenId = currentEpochFormatted*10000 + bet +1;
        const betDisplay = bet + 1;
        try {
          console.log("GEtting token index", tokenId);
          const tokenQty = await readContracts.Ballita.balanceOf(address, tokenId);
          const tokenQtyFormatted = tokenQty&&tokenQty.toNumber();
          console.log("owner", address);
          if(tokenQtyFormatted) collectibleUpdate.push({id: tokenId, qty: tokenQtyFormatted, owner: address, epoch: currentEpoch, bet: betDisplay})
        } catch (e) {
          console.log(e);
        }
      }
      setYourCollectibles(collectibleUpdate);
    };
    updateYourCollectibles();
  }, [address, buying, currentEpoch]);

  const [yourWinners, setYourWinners] = useState([]);

  useEffect(() => {

    const updateYourWinners = async () => {
      const winnersUpdate = [];
      let prevEpoch = 69;
      for(let i = 0; i < advanceEvents.length; i++){
        try{
          if(advanceEvents[i].args.previousEpoch.toNumber() != prevEpoch){
            prevEpoch = advanceEvents[i].args.previousEpoch.toNumber();
            const winningsForEpoch = await readContracts.Ballita.winnings(advanceEvents[i].args.previousEpoch);
            if(winningsForEpoch.numberOfWinners.toNumber()) {
              const winningIDForEpoch = prevEpoch * 10000 + winningsForEpoch.winningNumber.toNumber();
              const winningsForAddress = await readContracts.Ballita.balanceOf(address, winningIDForEpoch);
              if(winningsForAddress.toNumber()) winnersUpdate.push({id: winningIDForEpoch, qty: winningsForAddress.toNumber(), number: winningsForEpoch.winningNumber.toNumber(), amount: winningsForEpoch.prize, epoch: advanceEvents[i].args.previousEpoch.toNumber()});
            }
          }
        }catch (e) {
          console.log(e);
        }
      }
      setYourWinners(winnersUpdate);
    };
    updateYourWinners();
  },[address, currentEpoch, advanceEvents, claiming]);

  console.log("winners", yourWinners);

  return (
    <div>
      <div style={{marginTop: 32}}>
        <h1>charity address &nbsp;
        <Address
          address={charity}
          ensProvider={mainnetProvider}
          blockExplorer={blockExplorer}

        />
         &nbsp; recieves {charityPercent&&charityPercent.toNumber()}% of winnings</h1>
      </div>
      <div style={{marginTop: 24}}>
        <h2> Winning number from last round {async () => {
          const lastWinner = await readContracts.Ballita.winnings(previousEpoch)
          const lastWinningNumber = lastWinner&&lastWinner.winningNumber;
          return lastWinningNumber;
        }} </h2>
      </div>
      <div style={{marginTop: 16}}>
        <h2> Next Drawing {nextDrawing} <br /> (in {countdown} seconds) </h2>
      </div>
      <div style={{marginTop: 16}}>
        <Space>
        Place your bet (  1  -{topNumberFormatted})
          <InputNumber
            min={1}
            max={topNumberFormatted}
            placeholder={"number"}
            value={betNumber}
            onChange={setBetNumber}
          />
          <Button
            type="primary"
            disabled={timestamp >= currentEpochFormatted}
            loading={buying}
            onClick={async () => {
              setBuying(true);
              await tx(writeContracts.Ballita.mint(betNumber, { value: betPrice }));
              setBuying(false);
            }}
          >
           buy
         </Button>
        </Space>
      </div>
      <div style={{margin: "auto", marginTop: 32}}>
        <Button
          type="primary"
          disabled={timestamp < currentEpochFormatted}
          loading={buying}
          onClick={async () => {
            setBuying(true);
            await tx(writeContracts.Ballita.advanceEpoch());
            setBuying(false);
          }}
        >
         pull ball
       </Button>
      </div>

      {yourCollectibles.length?
        <div style={{ width: 640, margin: "auto", marginTop: 32, paddingBottom: 32 }}>
          <h2>your open bets</h2>
          <List
            bordered
            dataSource={yourCollectibles}
            renderItem={item => {
              const id = item.id;
              console.log("owner item", item.owner);
              return (
                <List.Item key={id + "_" + item.owner}>
                  <Card
                    title={
                      <div>
                        <span style={{ fontSize: 16, marginRight: 8 }}>#{id} qty: {item.qty}</span>
                      </div>
                    }
                  >
                    <div style={{fontSize: 72}}>{item.bet}</div>
                  </Card>

                  <div>
                    owner:{" "}
                    <Address
                      address={item.owner}
                      ensProvider={mainnetProvider}
                      blockExplorer={blockExplorer}
                      fontSize={16}
                    />
                  </div>
                </List.Item>
              );
            }}
          />
        </div>
        : ""
      }
      {yourWinners.length?
        <div style={{ width: 600, margin: "auto", marginTop: 32, paddingBottom: 150 }}>
          <h2>your winners</h2>
          <List
            bordered
            dataSource={yourWinners}
            renderItem={item => {
              return (
                <List.Item key={item.id}>
                  <Card
                    title={
                      <div>
                        <span style={{ fontSize: 16, marginRight: 8 }}>#{item.id} qty: {item.qty}</span>
                      </div>
                    }
                  >
                    <div style={{fontSize: 72}}>{item.number}</div>
                  </Card>
                  <div>
                    for <Balance balance={item.amount} price={price} fontSize={64} /> ea.
                  </div>
                  <div>
                    <Button
                      type="primary"
                      loading={claiming}
                      onClick={async () => {
                        setClaiming(true);
                        await tx(writeContracts.Ballita.claim(item.epoch, item.qty));
                        setClaiming(false);
                      }}
                    >
                     claim
                   </Button>
                  </div>
                </List.Item>
              );
            }}
          />
        </div>
        : ""
      }


    </div>
  );
}

export default Home;
