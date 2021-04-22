const std = @import("std");
const sha2 = std.crypto.hash.sha2;

const Hash = u256;
const Digest = [4]u64;

var leafCount: usize = 0;
var branchCount: usize = 0;
var maxLevel: usize = 0;

fn autoMap(comptime BLOCK_POWER: comptime_int) comptime type {
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
            branchCount += 1;
            const node = try self.allocator.create(Node);
            node.* = .{ .branch = .{null} ** BRANCH_FACTOR };
            return node;
        }

        fn newLeaf(self: *const Self, block: *const Block, digest: *const Digest) !*Node {
            leafCount += 1;
            const node = try self.allocator.create(Node);
            node.* = .{ .leaf = .{ .block = block.*, .digest = digest.* } };
            return node;
        }

        allocator: *std.mem.Allocator,
        root: ?*Node,

        pub fn init(allocator: *std.mem.Allocator) !Self {
            return Self{ .allocator = allocator, .root = null };
        }

        fn clearNode(self: *Self, node: *Node) void {
            switch (node.*) {
                Node.branch => |*branch| {
                    var i: usize = 0;
                    while (i < BRANCH_FACTOR) : (i += 1) {
                        if (branch[i]) |childNode| {
                            self.clearNode(childNode);
                            branch[i] = null;
                        }
                    }
                },
                Node.leaf => |*leaf| {},
            }
            self.allocator.destroy(node);
        }

        pub fn clear(self: *Self) void {
            if (self.root) |root| {
                self.clearNode(root);
                self.root = null;
            }
        }

        pub fn deinit(self: *Self) void {
            self.clear();
            self.* = undefined;
        }

        pub fn walk(self: *Self) void {
            std.debug.print("\nWALK {*} rootNode={*}\n", .{ self, self.root });
            self.walkNode(self.root, 0);
            std.debug.print("\n", .{});
        }

        fn walkNode(self: *Self, maybeNode: ?*Node, comptime depth: u8) void {
            if (depth > 10) return;
            if (maybeNode) |node| {
                switch (node.*) {
                    Node.branch => |*branch| {
                        std.debug.print("{s}  {*}\n", .{ "  " ** depth, branch });
                        for (branch) |childNode| {
                            self.walkNode(childNode, depth + 2);
                        }
                    },
                    Node.leaf => |*leaf| {
                        std.debug.print("{s}  {*}\n", .{ "  " ** depth, leaf });
                    },
                }
            }
        }

        // Convert a digest to a big endian number.
        fn digestToHash(digest: *const Digest) Hash {
            return (@intCast(u256, std.mem.bigToNative(u64, digest[0])) << 192) | (@intCast(u256, std.mem.bigToNative(u64, digest[1])) << 128) | (@intCast(u256, std.mem.bigToNative(u64, digest[2])) << 64) | (@intCast(u256, std.mem.bigToNative(u64, digest[3])) << 0);
        }

        pub fn fetch(self: *Self, digest: *const Digest) ?*const Block {
            // Get the numerical version of the hash so we can walk he bits.
            const hash = digestToHash(digest);
            var index: u8 = 0;
            var node: ?*Node = self.root;
            while (index < (256 / BRANCH_POWER)) : (index += 1) {
                if (node) |realNode| {
                    switch (realNode.*) {
                        Node.branch => |*branch| {
                            // Walk down a branch if found...
                            node = branch[getBitSlice(hash, index)];
                        },
                        Node.leaf => |*leaf| {
                            if (std.mem.eql(u64, &(leaf.digest), digest)) {
                                return &(leaf.block);
                            }
                            break;
                        },
                    }
                } else {
                    break;
                }
            }
            // I guess it wasn't there.
            return null;
        }

        pub fn store(self: *Self, block: *const Block, digest: *Digest) !void {

            // First calculate the SHA256 digest of the block of data.
            sha2.Sha256.hash(block, @ptrCast(*[32]u8, digest), .{});

            // Convert it into a giant number (interpreted as big endian)
            const hash = digestToHash(digest);

            var index: u8 = 0;
            var node: *?*Node = &(self.root);
            while (index < (256 / BRANCH_POWER)) : (index += 1) {
                if (index > maxLevel) maxLevel = index;
                if (node.*) |*realNode| {
                    switch (realNode.*.*) {
                        Node.branch => |*branch| {
                            // Walk down branch...
                            node = &(branch[getBitSlice(hash, index)]);
                        },
                        Node.leaf => |*leaf| {
                            if (std.mem.eql(u64, &(leaf.digest), digest)) {
                                return;
                            }

                            // We need to split this leaf into a branch and two leaves.
                            const branch: *Node = try self.newBranch();
                            // Move the old leaf to the new branch.
                            branch.branch[getBitSlice(digestToHash(&leaf.digest), index)] = realNode.*;
                            // Move the pointer to the new branch.
                            node.* = branch;
                            // Walk down the new branch.
                            node = &(branch.branch[getBitSlice(hash, index)]);
                        },
                    }
                } else {
                    node.* = try self.newLeaf(block, digest);
                    return;
                }
            }
        }
        // Get a slice of bits from the giant hash value.
        fn getBitSlice(hash: Hash, index: u32) usize {
            const offset = @intCast(u8, index * BRANCH_POWER);
            return @intCast(usize, (hash >> offset) & ((2 << (BRANCH_POWER - 1)) - 1));
        }
    };
}

test "Check for leaks in init/deinit" {
    inline for (.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) |BLOCK_POWER| {
        const Map = autoMap(BLOCK_POWER);
        var map = try Map.init(std.testing.allocator);
        defer map.deinit();
    }
}

// The number of bits consumed per recursion is optimized to be the maximum amount
// that keeps the branch nodes no bigger than the leaf nodes.
test "Ensure proper branch factor" {
    inline for (.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) |BLOCK_POWER| {
        const Map = autoMap(BLOCK_POWER);
        std.testing.expect(@sizeOf(Map.Branch) <= @sizeOf(Map.Leaf));
    }
}

test "reading and writing..." {
    inline for (.{ 3, 6, 9, 12, 15 }) |BLOCK_POWER| {
        const Map = autoMap(BLOCK_POWER);
        // std.debug.print("\nBLOCK_POWER = {}\n", .{BLOCK_POWER});
        // std.debug.print("Map.BLOCK_SIZE = {}\n", .{Map.BLOCK_SIZE});
        // std.debug.print("Map.BRANCH_POWER = {}\n", .{Map.BRANCH_POWER});

        var map = try Map.init(std.testing.allocator);

        defer map.deinit();
        maxLevel = 0;
        branchCount = 0;
        leafCount = 0;

        var block: Map.Block = .{0} ** Map.BLOCK_SIZE;
        var digest: Digest = undefined;
        var i: u32 = 0;
        const inserts = 0x8000 >> BLOCK_POWER;
        while (i < inserts) : (i += 1) {
            block[0] = @intCast(u8, i & 0xff);
            block[1] = @intCast(u8, (i >> 8) & 0xff);
            block[2] = @intCast(u8, (i >> 16) & 0xff);
            block[3] = @intCast(u8, (i >> 24) & 0xff);
            try map.store(&block, &digest);

            // Make sure we can retrieve it back.
            const stored1: *const Map.Block = map.fetch(&digest) orelse return error.NotFound;
            std.testing.expectEqualSlices(u8, &block, stored1);

            // test with end of hash wrong and verify it's not found.
            digest[3] += 1;
            std.testing.expectEqual(map.fetch(&digest), null);

            // Store it again to test duplicates
            try map.store(&block, &digest);

            // Make sure we can retrieve it back again
            const stored2: *const Map.Block = map.fetch(&digest) orelse return error.NotFound;
            std.testing.expectEqualSlices(u8, &block, stored2);
            // Make sure it stored a copy of the memory we gave it.
            std.testing.expect(stored2 != &block);

            // Test with start of hash wrong and verify it's not found.
            digest[0] += 1;
            std.testing.expectEqual(map.fetch(&digest), null);
        }
        // std.debug.print("levels: {} - branches: {} - leaves: {}\n", .{ maxLevel, branchCount, leafCount });
        std.testing.expectEqual(leafCount, inserts);
    }
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;
    // const allocator = std.heap.page_allocator;

    const Map = autoMap(10);
    var map = try Map.init(allocator);
    // defer map.deinit();

    map.walk();
    var block: Map.Block = .{0} ** Map.BLOCK_SIZE;
    var digest: Digest = undefined;
    var i: u8 = 0;
    while (i < 255) : (i += 1) {
        std.debug.print("levels: {} - branches: {} - leaves: {}\n", .{ maxLevel, branchCount, leafCount });
        block[0] = i;
        var j: u8 = 0;
        while (j < 255) : (j += 1) {
            block[1] = j;
            var k: u8 = 0;
            while (k < 255) : (k += 1) {
                block[2] = k;
                // std.debug.print("\ndigest = {*} | {x:8} {x:8} {x:8} {x:8}\n", .{ &digest, digest[0], digest[1], digest[2], digest[3] });
                map.store(&block, &digest) catch |err| {
                    std.debug.print("levels: {} - branches: {} - leaves: {}\n", .{ maxLevel, branchCount, leafCount });
                    return err;
                };
            }
        }
    }
    // map.walk();

    map.clear();
    map.walk();
    // std.debug.print("\ndigest = {*} | {x:8} {x:8} {x:8} {x:8}\n", .{ &digest, digest[0], digest[1], digest[2], digest[3] });
}
