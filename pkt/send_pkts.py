
#!/usr/bin/env python3

import socket
import random
from time import sleep

from scapy.all import (
    IP,
    UDP,
    Ether,
    IntField,
    BitField,
    Packet,
    get_if_hwaddr,
    get_if_list,
    bind_layers,
    sendp
)

# Number of tuples to generate
NUMBER_ENTRIES = 10
# Generate randomly the entityIds from a range of 0 to 1000
RANDOM_ENTITYIDS = random.sample(range(0, 1000), 4)

def get_if():
    ifs=get_if_list()
    iface=None # "h1-eth0"
    for i in get_if_list():
        if "veth1" in i:
            iface=i
            break;
    if not iface:
        print("Cannot find veth1 interface")
        exit(1)
    return iface

class DBEntry(Packet):
    fields_desc = [ 
        IntField("entryId", 0),
        IntField("secondAttr", 0),
        IntField("thirdAttr", 0),
    ]

class DBRelation(Packet):
    name = "MYP4DB_Relation"
    fields_desc = [ 
        BitField("relationId", 0, 7),
        BitField("aggregate", 0, 1),
    ]

# IP proto 250 indicates MYP4DB_Relation
bind_layers(IP, DBRelation, proto=0xFA)
bind_layers(DBRelation, DBEntry)
# If bottom of stack has reached, then UDP header will follow
bind_layers(DBEntry, UDP)

# Generate MYP4DB packet and append it to an existing ipv4 packet
def generate_db_pkt(pkt, entityId=0, pick_random_entityId=False):
    # Pick a new random entity if random generator returns false
    if pick_random_entityId:
        entityId = random.choice(RANDOM_ENTITYIDS)
    secondAttr = random.randint(0, 5)
    thirdAttr = random.randint(0, 5)
    # Append to the header stack
    try:
        pkt = pkt / DBEntry(entryId=int(entityId), secondAttr=int(secondAttr), thirdAttr=int(thirdAttr))
    except ValueError:
        pass
        
    pkt = pkt / UDP(dport=4321, sport=1234) / "P4 is cool"
    return pkt

def main():
    
    addr = socket.gethostbyname("10.0.2.2")
    iface = get_if()

    # Generate the first relation, which will be stored on the switch
    for i in range(0, NUMBER_ENTRIES):
        pkt = Ether(src=get_if_hwaddr(iface), dst="ff:ff:ff:ff:ff:ff") / IP(dst=addr, proto=0xFA) / DBRelation(relationId=1)
        r_relation = generate_db_pkt(pkt, pick_random_entityId=True)

        r_relation.show2()
        iface = get_if()
        # Send packet
        sendp(r_relation, iface=iface)

    try:
        sleep(1)
    except KeyboardInterrupt:
        raise

    for entityId in RANDOM_ENTITYIDS:
        pkt = Ether(src=get_if_hwaddr(iface), dst="ff:ff:ff:ff:ff:ff") / IP(dst=addr, proto=0xFA) / DBRelation(relationId=1)
        r_relation = generate_db_pkt(pkt, entityId)

        r_relation.show2()
        iface = get_if()
        # Send packet
        sendp(r_relation, iface=iface)


if __name__ == '__main__':
    main()