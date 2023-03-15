# Tofino P4 application for table aggregation (sum function)
This P4 application is a toy example, which implements a table aggragation from a relation grouped by entityId within the dataplane. This P4 application has been build for the Intel Tofino Native architecture.

## Overview
Let's assume we have a single table/relation, called `R`, and it has three (unsigned) integer attributes.

First we pump the table `R` with random numbers to the switch. The switch will store these tuples in a hash table using `extern Register`.

### Example
**Relation R**
| entityId | secondAttr | thirdAttr |
|----------|------------|-----------|
| 153      | 2          | 5         |
| 153      | 3          | 5         |
| 153      | 1          | 6         |
| 789      | 685        | 145       |

**Result**
| entityId | secondAttr | thirdAttr |
|----------|------------|-----------|
| 153      | 6          | 16        |
| 789      | 685        | 145       |

## Design
After the IPv4 header, the [MYP4DB_Relation](#relational-header-myp4db_relation) header will be appended, which contains the metadata for a relation. IPv4 protocol number 0xFA (250) is used to indicate that header.
An additional header of type [DBEntry](#request-tuple-dbentry) will follow, which contains a single tuple.

The switch will process the tuple from the header and it will return the aggregation. 

### Relational Header (MYP4DB_Relation)
```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  relationId |a|
+-+-+-+-+-+-+-+-+

```
Total 1 byte (8-bits)
* relationId (7-bit): the name of the relation represented as an unsigned integer. 
* reserved (1-bit): not used

### Request Tuple (DBEntry)
```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           entryId                             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           secondAttr                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           thirdAttr                           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```
Total 12 bytes (96 bits)
* entryId (32-bit): primary key represented as an unsigned integer.
* secondAttr (32-bit): Second attribute of the tuple represented as an unsigned integer.
* thirdAttr (32-bit): Third attribute of the tuple represented as an unsigned integer.

## Example
* Start the switch simulator running our P4 code.
* In a new terminal, execute `sniff_pkts.py` script
```
sudo python3 bfrt_python/sniff_pkts.py
```
* In a new terminal, execute `send_pkts.py` script to send requests
```
sudo python3 bfrt_python/send_pkts.py
```

### Example output
20 packets will be sent from h1. EntityIds will be randomly reused. We will retrieve the sum per attribute grouped by entitiyId.

#### 2 samples sent by h1
```###[ Ethernet ]### 
  dst       = ff:ff:ff:ff:ff:ff
  src       = 08:00:00:00:01:11
  type      = IPv4
###[ IP ]### 
     version   = 4
     ihl       = 5
     tos       = 0x0
     len       = 51
     id        = 1
     flags     = 
     frag      = 0
     ttl       = 64
     proto     = 250
     chksum    = 0x62ce
     src       = 10.0.1.1
     dst       = 10.0.2.2
     \options   \
###[ MYP4DB_Relation ]### 
        relationId= 1
        aggregate = 0
###[ DBEntry ]### 
           entryId   = 799
           secondAttr= 1
           thirdAttr = 3
###[ UDP ]### 
              sport     = 1234
              dport     = 4321
              len       = 18
              chksum    = 0x0
###[ Raw ]### 
                 load      = 'P4 is cool'

###[ Ethernet ]### 
  dst       = ff:ff:ff:ff:ff:ff
  src       = 08:00:00:00:01:11
  type      = IPv4
###[ IP ]### 
     version   = 4
     ihl       = 5
     tos       = 0x0
     len       = 51
     id        = 1
     flags     = 
     frag      = 0
     ttl       = 64
     proto     = 250
     chksum    = 0x62ce
     src       = 10.0.1.1
     dst       = 10.0.2.2
     \options   \
###[ MYP4DB_Relation ]### 
        relationId= 1
        aggregate = 0
###[ DBEntry ]### 
           entryId   = 383
           secondAttr= 2
           thirdAttr = 4
###[ UDP ]### 
              sport     = 1234
              dport     = 4321
              len       = 18
              chksum    = 0x0
###[ Raw ]### 
                 load      = 'P4 is cool'
```
#### Retrieved packets on h2
```
got a packet
###[ Ethernet ]### 
  dst       = 08:00:00:00:02:22
  src       = ff:ff:ff:ff:ff:ff
  type      = IPv4
###[ IP ]### 
     version   = 4
     ihl       = 5
     tos       = 0x0
     len       = 51
     id        = 1
     flags     = 
     frag      = 0
     ttl       = 63
     proto     = 250
     chksum    = 0x63ce
     src       = 10.0.1.1
     dst       = 10.0.2.2
     \options   \
###[ MYP4DB_Relation ]### 
        relationId= 1
        aggregate = 1
###[ DBEntry ]### 
           entryId   = 383
           secondAttr= 11
           thirdAttr = 12
###[ UDP ]### 
              sport     = 1234
              dport     = 4321
              len       = 18
              chksum    = 0x0
###[ Raw ]### 
                 load      = 'P4 is cool'

got a packet
###[ Ethernet ]### 
  dst       = 08:00:00:00:02:22
  src       = ff:ff:ff:ff:ff:ff
  type      = IPv4
###[ IP ]### 
     version   = 4
     ihl       = 5
     tos       = 0x0
     len       = 51
     id        = 1
     flags     = 
     frag      = 0
     ttl       = 63
     proto     = 250
     chksum    = 0x63ce
     src       = 10.0.1.1
     dst       = 10.0.2.2
     \options   \
###[ MYP4DB_Relation ]### 
        relationId= 1
        aggregate = 1
###[ DBEntry ]### 
           entryId   = 773
           secondAttr= 9
           thirdAttr = 4
###[ UDP ]### 
              sport     = 1234
              dport     = 4321
              len       = 18
              chksum    = 0x0
###[ Raw ]### 
                 load      = 'P4 is cool'

got a packet
###[ Ethernet ]### 
  dst       = 08:00:00:00:02:22
  src       = ff:ff:ff:ff:ff:ff
  type      = IPv4
###[ IP ]### 
     version   = 4
     ihl       = 5
     tos       = 0x0
     len       = 51
     id        = 1
     flags     = 
     frag      = 0
     ttl       = 63
     proto     = 250
     chksum    = 0x63ce
     src       = 10.0.1.1
     dst       = 10.0.2.2
     \options   \
###[ MYP4DB_Relation ]### 
        relationId= 1
        aggregate = 1
###[ DBEntry ]### 
           entryId   = 186
           secondAttr= 3
           thirdAttr = 8
###[ UDP ]### 
              sport     = 1234
              dport     = 4321
              len       = 18
              chksum    = 0x0
###[ Raw ]### 
                 load      = 'P4 is cool'

got a packet
###[ Ethernet ]### 
  dst       = 08:00:00:00:02:22
  src       = ff:ff:ff:ff:ff:ff
  type      = IPv4
###[ IP ]### 
     version   = 4
     ihl       = 5
     tos       = 0x0
     len       = 51
     id        = 1
     flags     = 
     frag      = 0
     ttl       = 63
     proto     = 250
     chksum    = 0x63ce
     src       = 10.0.1.1
     dst       = 10.0.2.2
     \options   \
###[ MYP4DB_Relation ]### 
        relationId= 1
        aggregate = 1
###[ DBEntry ]### 
           entryId   = 799
           secondAttr= 2
           thirdAttr = 3
###[ UDP ]### 
              sport     = 1234
              dport     = 4321
              len       = 18
              chksum    = 0x0
###[ Raw ]### 
                 load      = 'P4 is cool'
```
