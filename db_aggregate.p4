/* -*- P4_16 -*- */
#include <core.p4>
/* TOFINO Native architecture */
#include <t2na.p4>

/* Max hash table cells */
#define NB_CELLS 1024

const bit<16> TYPE_IPV4 = 0x800;
const bit<8> TYPE_MYP4DB = 0xFA;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;
typedef bit<32> db_attribute_t;
typedef bit<10> hashedKey_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

header db_relation_t {
    bit<7>  relationId;
    bit<1>  aggregate;
}

header db_tuple_t {
    db_attribute_t  entryId;
    db_attribute_t  secondAttr;
    db_attribute_t  thirdAttr;
}

struct metadata {
    
}

struct db_values_t {
    db_attribute_t secondAttr;
    db_attribute_t thirdAttr;
}

struct headers {
    ethernet_t          ethernet;
    ipv4_t              ipv4;
    db_relation_t       db_relation;
    db_tuple_t          db_tuple;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser DBTupleParser(packet_in packet, out headers hdr) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            TYPE_MYP4DB     : parse_relation;
            default         : accept;
        }
    }

    /* Parse the relation header */ 
    state parse_relation {
        packet.extract(hdr.db_relation);
        transition parse_entries;
    }

    /*  Parse the db_tuple header */
    state parse_entries {
        packet.extract(hdr.db_tuple);
        transition accept;
    }
}

parser SwitchIngressParser(packet_in packet,
                out headers hdr,
                out metadata meta,
                out ingress_intrinsic_metadata_t ig_intr_md) {
    
    DBTupleParser() dbTupleParser;

    state start {
        /* TNA-specific Code for simple cases */
        packet.extract(ig_intr_md);
        packet.advance(PORT_METADATA_SIZE);

        dbTupleParser.apply(packet, hdr);

        transition accept;
    }
}

parser SwitchEgressParser(packet_in packet,
                out headers hdr,
                out metadata meta,
                out egress_intrinsic_metadata_t eg_intr_md) {

    DBTupleParser() dbTupleParser;

    state start {
        /* TNA-specific Code for simple cases */
        packet.extract(eg_intr_md);

        dbTupleParser.apply(packet, hdr);

        transition accept;
    }
}

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control SwitchIngress(inout headers hdr,
                  inout metadata meta,
                  /* Intrinsic */
                  in ingress_intrinsic_metadata_t                     ig_intr_md, 
                  in ingress_intrinsic_metadata_from_parser_t         ig_prsr_md,
                  inout ingress_intrinsic_metadata_for_deparser_t     ig_dprsr_md,
                  inout ingress_intrinsic_metadata_for_tm_t           ig_tm_md) {
    
    // Hash function for hashing key in the hash table
    Hash<hashedKey_t>(HashAlgorithm_t.CRC16) crc16Hashfct;

    // Initialize hash table with value 0
    Register<db_values_t, hashedKey_t>(NB_CELLS, {0, 0}) database;

    // Updates the database with the values from PHV
    RegisterAction2<db_values_t, hashedKey_t, db_attribute_t, db_attribute_t>(database) db_update_action = {
        void apply(inout db_values_t value, out db_attribute_t secondAttr, out db_attribute_t thirdAttr) {
            // Aggregate the values (SUM)
            value.secondAttr = value.secondAttr + hdr.db_tuple.secondAttr;
            value.thirdAttr = value.thirdAttr + hdr.db_tuple.thirdAttr;
            // Return the current values
            secondAttr = value.secondAttr;
            thirdAttr = value.thirdAttr;
        }
    };

    action drop() {
        ig_dprsr_md.drop_ctl = 0x1; // drop packet.
    }

    action ipv4_forward(macAddr_t dstAddr, PortId_t port) {
        ig_tm_md.ucast_egress_port = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            ipv4_forward;
            drop;
            NoAction;
        }
        size = 16;
        default_action = drop();
    }

    apply {
        // Run IPv4 routing logic.
        ipv4_lpm.apply();

        if (hdr.db_relation.isValid()) {
            hashedKey_t hashedKey = 0;
            db_attribute_t newSecondAttr = 0;
            db_attribute_t newThirdAttr = 0;

            // Hash the primary key (entryId)
            hashedKey = crc16Hashfct.get({ hdr.db_tuple.entryId });

            // Insert tuple in the hash table
            // SUM the values, update the database, return aggregated values
            newSecondAttr = db_update_action.execute(hashedKey, newThirdAttr);

            // Prepare response
            hdr.db_tuple.secondAttr = newSecondAttr;
            hdr.db_tuple.thirdAttr = newThirdAttr;
        }    
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control SwitchEgress(inout headers hdr,
                 inout metadata meta,
                 /* Intrinsic */
                 in egress_intrinsic_metadata_t                      eg_intr_md,
                 in egress_intrinsic_metadata_from_parser_t          eg_prsr_md,
                 inout egress_intrinsic_metadata_for_deparser_t      eg_dprsr_md,
                 inout egress_intrinsic_metadata_for_output_port_t   eg_oport_md) {

    apply {

    }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control SwitchIngressDeparser(packet_out packet, 
                              inout headers hdr,
                              in metadata meta,
                              /* Intrinsic */
                              in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {

    Checksum() checksumfct;

    apply {
        //Update IPv4 checksum
        hdr.ipv4.hdrChecksum = checksumfct.update({ 
            hdr.ipv4.version,
            hdr.ipv4.ihl,
            hdr.ipv4.diffserv,
            hdr.ipv4.totalLen,
            hdr.ipv4.identification,
            hdr.ipv4.flags,
            hdr.ipv4.fragOffset,
            hdr.ipv4.ttl,
            hdr.ipv4.protocol,
            hdr.ipv4.srcAddr,
            hdr.ipv4.dstAddr 
        });

        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.db_relation);
        packet.emit(hdr.db_tuple);
    }
}

control SwitchEgressDeparser(packet_out packet,
                             inout headers hdr,
                             in metadata meta,
                             /* Intrinsic */
                             in egress_intrinsic_metadata_for_deparser_t eg_dprsr_md) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.db_relation);
        packet.emit(hdr.db_tuple);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

Pipeline(
    SwitchIngressParser(), 
    SwitchIngress(), 
    SwitchIngressDeparser(), 
    SwitchEgressParser(), 
    SwitchEgress(), 
    SwitchEgressDeparser()
) pipe;
Switch(pipe) main;