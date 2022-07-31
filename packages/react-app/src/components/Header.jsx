import { PageHeader } from "antd";
import React from "react";

// displays a page header

export default function Header() {
  return (
    <a href="https://github.com/0xWildhare/ballita.git" target="_blank" rel="noopener noreferrer">
      <PageHeader
        title="Ballita"
        subTitle="forkable"
        style={{ cursor: "pointer" }}
      />
    </a>
  );
}
