const std = @import("std");
const sha2 = std.crypto.hash.sha2;

const Hash = u256;
const Digest = [4]u64;

fn AutoMap(comptime BLOCK_POWER: comptime_int) type {
    return struct {
        const Self = @This();

        const BLOCK_SIZE = 2 << (BLOCK_POWER - 1);
        const BRANCH_POWER = std.math.log2(@sizeOf(Leaf) / @sizeOf(?*u8));
        const BRANCH_FACTOR = 2 << (BRANCH_POWER - 1);
        const Block = [BLOCK_SIZE]u8;
        const Leaf = struct { block: Block, digest: Digest };
        const Branch = [BRANCH_FACTOR]?*Node;
        const Node = union(enum) { branch: Branch, leaf: Leaf };

        fn newBranch(self: *const Self) !*Node {
            const node = try self.allocator.create(Node);
            node.* = .{ .branch = .{null} ** BRANCH_FACTOR };
            return node;
        }

        fn newLeaf(self: *const Self, block: *const Block, digest: *const Digest) !*Node {
            const node = try self.allocator.create(Node);
            node.* = .{ .leaf = .{ .block = block.*, .digest = digest.* } };
            return node;
        }

        allocator: *std.mem.Allocator,
        root: ?*Node,

        pub fn init(comptime allocator: *std.mem.Allocator) !Self {
            return Self{ .allocator = allocator, .root = null };
        }

        pub fn deinit(self: *Self) void {
            // const root = self.root;
            // self.root.* = undefined;
            // self.allocator.destroy(root);
            self.* = undefined;
        }

        // Convert a digest to a big endian number.
        fn digestToHash(digest: *const Digest) Hash {
            return (@intCast(u256, std.mem.bigToNative(u64, digest[0])) << 192) | (@intCast(u256, std.mem.bigToNative(u64, digest[1])) << 128) | (@intCast(u256, std.mem.bigToNative(u64, digest[2])) << 64) | (@intCast(u256, std.mem.bigToNative(u64, digest[3])) << 0);
        }

        pub fn store(self: *Self, block: *const Block, digest: *Digest) !void {

            // First calculate the SHA256 digest of the block of data.
            sha2.Sha256.hash(block, @ptrCast(*[32]u8, digest), .{});

            // Convert it into a giant number (interpreted as big endian)
            const hash = digestToHash(digest);

            var index: u8 = 0;
            if (self.root) |rootNode| {
                var node: *Node = rootNode;
                while (index < (256 / BRANCH_POWER)) : (index += 1) {
                    switch (node.*) {
                        Node.branch => |*branch| {
                            const slice = getBitSlice(hash, index);
                            if (branch[slice]) |childNode| {
                                std.debug.print("index = {} | Walking down node... | slice = 0x{x}\n", .{ index, slice });
                                node = childNode;
                            } else {
                                branch[slice] = try self.newLeaf(block, digest);
                                return;
                            }
                        },
                        Node.leaf => |leaf| {
                            std.debug.print("Found old leaf {x:16} x{:16}\n", .{ leaf.digest[0], leaf.digest[1] });
                            // TODO: check if existing leaf is same as the one we're writing...
                            const slice = getBitSlice(hash, index);
                            std.debug.print("\nindex = {} | converting leaf into branch and two leaves\n", .{index});
                            var branch = try self.newBranch();
                            // Move the old leaf to the new branch.
                            branch.branch[getBitSlice(digestToHash(&leaf.digest), index)] = node;
                            // Create a new leaf for the new value.
                            branch.branch[slice] = try self.newLeaf(block, digest);
                            // Move the pointer to the new branch.
                            node = branch;
                        },
                    }
                }
            } else {
                std.debug.print("Setting new root node as leaf...\n", .{});
                self.root = try self.newLeaf(block, digest);
                return;
            }
        }
        // Get a slice of bits from the giant hash value.
        fn getBitSlice(hash: Hash, index: u32) u64 {
            const offset = @intCast(u8, index * BRANCH_POWER);
            return @intCast(u64, (hash >> offset) & ((2 << (BRANCH_POWER - 1)) - 1));
        }
    };
}

test "Check for leaks in init/deinit" {
    inline for (.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) |BLOCK_POWER| {
        const Map = AutoMap(BLOCK_POWER);
        var map = try Map.init(std.testing.allocator);
        defer map.deinit();
    }
}

// The number of bits consumed per recursion is optimized to be the maximum amount
// that keeps the branch nodes no bigger than the leaf nodes.
test "Ensure proper branch factor" {
    inline for (.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) |BLOCK_POWER| {
        const Map = AutoMap(BLOCK_POWER);
        std.testing.expect(@sizeOf(Map.Branch) <= @sizeOf(Map.Leaf));
    }
}

test "write" {
    const Map = AutoMap(12);
    var map = try Map.init(std.testing.allocator);
    defer map.deinit();

    var block: Map.Block = .{0} ** Map.BLOCK_SIZE;
    var digest: Digest = undefined;
    try map.store(&block, &digest);
    std.debug.print("\ndigest = {*} | {x:8} {x:8} {x:8} {x:8}\n", .{ &digest, digest[0], digest[1], digest[2], digest[3] });
    block[0] = 1;
    try map.store(&block, &digest);
    std.debug.print("\ndigest = {*} | {x:8} {x:8} {x:8} {x:8}\n", .{ &digest, digest[0], digest[1], digest[2], digest[3] });
    block[0] = 2;
    try map.store(&block, &digest);
    std.debug.print("\ndigest = {*} | {x:8} {x:8} {x:8} {x:8}\n", .{ &digest, digest[0], digest[1], digest[2], digest[3] });
}

// test "walk" {
//     inline for (.{ 10, 12, 15 }) |BLOCK_POWER| {
//         const Map = AutoMap(BLOCK_POWER);
//         std.debug.print("\nBLOCK_POWER = {}\n", .{BLOCK_POWER});
//         std.debug.print("Map.BLOCK_SIZE = {}\n", .{Map.BLOCK_SIZE});
//         std.debug.print("Map.BRANCH_POWER = {}\n", .{Map.BRANCH_POWER});
//         // std.debug.print("Map.BRANCH_FACTOR = {}\n", .{Map.BRANCH_FACTOR});
//         // std.debug.print("@sizeOf(Map.Hash) = {}\n", .{@sizeOf(Map.Hash)});
//         // std.debug.print("@sizeOf(Map.Block) = {}\n", .{@sizeOf(Map.Block)});
//         // std.debug.print("@sizeOf(Map.Branch) = {}\n", .{@sizeOf(Map.Branch)});
//         // std.debug.print("@sizeOf(Map.Leaf) = {}\n", .{@sizeOf(Map.Leaf)});
//         // std.debug.print("@sizeOf(?*Map.Node) = {}\n", .{@sizeOf(?*Map.Node)});

//         const hash: Hash = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
//         comptime var index: u32 = 0;
//         std.debug.print("BRANCH_POWER = {}\n", .{Map.BRANCH_POWER});
//         inline while (index * Map.BRANCH_POWER < @bitSizeOf(@TypeOf(hash))) {
//             const bits = Map.getBitSlice(hash, index);
//             std.debug.print("index = {} bits = 0x{x}\n", .{ index, bits });
//             index += 1;
//         }
//     }
// }

// pub fn main() anyerror!void {

//     std.log.info("All your codebase are belong to us.", .{});
// }
