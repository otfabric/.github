# OT Fabric

**Unified data for industrial operations.**

Built by people and AI agents together, OT Fabric creates open-source protocol libraries and tools that break down OT data silos, so industrial data is easy to discover, access and use across systems, sites and teams.

## Why

Industrial data is valuable, but it is locked inside PLCs, RTUs, meters, inverters and building controllers. Every device speaks its own protocol, documentation is often incomplete, and integrations are rebuilt from scratch for every site and vendor. Teams spend their time fighting connectivity instead of using the data.

At the same time, the opportunity has never been bigger. Interconnecting devices unlocks better operations in factories, buildings and infrastructure. Energy is one of the clearest examples: a sustainable, decentralized grid only works when solar inverters, batteries, meters and substations can exchange data reliably.

We think the foundation for industrial connectivity should be open, well tested and reusable, so that nobody has to solve the same protocol problem twice.

## What we build

**Protocol libraries.** Pure Go clients and servers, built for production use:

| Protocol | Library | CLI |
|---|---|---|
| OPC UA | [go-opcua](https://github.com/otfabric/go-opcua) | [opcuactl](https://github.com/otfabric/opcuactl) |
| Modbus TCP/RTU | [go-modbus](https://github.com/otfabric/go-modbus) | [modbusctl](https://github.com/otfabric/modbusctl), [modbus-simulator](https://github.com/otfabric/modbus-simulator) |
| IEC 60870-5-104 | [go-iec104](https://github.com/otfabric/go-iec104) | [iec104ctl](https://github.com/otfabric/iec104ctl) |
| IEC 61850 / MMS | [go-iec61850](https://github.com/otfabric/go-iec61850), [go-mms](https://github.com/otfabric/go-mms) | [iec61850ctl](https://github.com/otfabric/iec61850ctl) |
| BACnet/IP | [go-bacnet](https://github.com/otfabric/go-bacnet) | [bacnetctl](https://github.com/otfabric/bacnetctl) |
| Siemens S7 | [go-s7comm](https://github.com/otfabric/go-s7comm) | [s7commctl](https://github.com/otfabric/s7commctl) |
| SunSpec | [go-sunspec](https://github.com/otfabric/go-sunspec) | [sunspecctl](https://github.com/otfabric/sunspecctl) |

**Transport building blocks.** [go-cotp](https://github.com/otfabric/go-cotp), [go-tpkt](https://github.com/otfabric/go-tpkt) and [go-serial](https://github.com/otfabric/go-serial) for ISO-on-TCP and RS-232/RS-485 links.

**Discovery.** [go-otfp](https://github.com/otfabric/go-otfp) fingerprints OT protocols so you can see what is actually running on a network.

**Interoperability testing.** Dockerized and fixture-based suites run our implementations against other stacks: [opcua-interop](https://github.com/otfabric/opcua-interop), [modbus-interop](https://github.com/otfabric/modbus-interop), [iec104-interop](https://github.com/otfabric/iec104-interop), [bacnet-interop](https://github.com/otfabric/bacnet-interop), [mms-interop](https://github.com/otfabric/mms-interop) and [snap7-interop](https://github.com/otfabric/snap7-interop).

## How we build

OT Fabric is built by people and AI agents working together. We are heading toward a reality where LLMs write better code and deliver more secure software, and we build for that reality today. Engineers bring the domain knowledge of real OT systems, set direction and own every decision. Agents bring speed, breadth and tireless attention to detail. Each makes the other better.

Speed alone is not the goal. Industrial protocols leave no room for "mostly works," so everything we ship, whoever or whatever wrote it, is held to the same bar: public code, public tests and interoperability suites that check it against other implementations. Our repositories are written to be easy for agents to work in, and for people to review, so contributors can bring their own agents too.

## Principles

- **Practical.** Built for real OT networks: legacy devices, private networks and imperfect documentation.
- **Open, MIT first.** Public code and public tests under the MIT license by default, so anyone can use, inspect and build on how a device is being talked to.
- **Modular.** Use one library, one CLI or the whole stack.
- **Proven.** If it ships, it interoperates. That is why every protocol gets a test suite.
- **Observable.** Diagnostics and visibility are built in from the start.
- **People and agents.** Built by engineers and AI agents together, and structured so both can understand, extend and test the code.

## Where we're heading

The protocol layer is the foundation. From there, we're building toward:

- **Full coverage of all relevant OT protocols**, so any industrial device can be reached with the same open, tested toolkit.
- **IT2OT gateways and data connectors** that move OT data safely into the IT, cloud and analytics systems that need it.
- **OT MCP servers for agentic interaction**, giving AI agents a structured, safe way to discover, read and work with industrial devices.

## Who it's for

- **Energy and electricity startups** moving the needle on sustainability: building the software that connects solar, storage, EV charging, grid and DER equipment in an increasingly connected world.
- **OT and automation engineers** who commission, troubleshoot and maintain field devices.
- **System integrators** who connect equipment from many vendors across many sites.
- **SCADA and edge builders** who need dependable protocol stacks.
- **Data and software teams** who need reliable access to industrial devices.

## Get involved

Everything is MIT-licensed unless a repository says otherwise. Try a CLI, open an issue, or contribute a fix, written by you, your AI agent or both of you. If you work on industrial connectivity, we'd love to hear from you at [otfabric.io](https://otfabric.io).
