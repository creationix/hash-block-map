const std = @import("std");

const Hash = u256;

fn AutoMap(comptime BLOCK_POWER: comptime_int) type {
    return struct {
        const Self = @This();

        const BLOCK_SIZE = 2 << (BLOCK_POWER - 1);
        const BRANCH_POWER = std.math.log2(@sizeOf(Leaf) / @sizeOf(?*u8));
        const BRANCH_FACTOR = 2 << (BRANCH_POWER - 1);
        const Block = [BLOCK_SIZE]u8;
        const Leaf = struct { block: Block, hash: Hash };
        const Branch = [BRANCH_FACTOR]?*Node;
        const Node = union(enum) { branch: Branch, leaf: Leaf };

        fn emptyBranch() Node {
            return .{ .branch = .{null} ** BRANCH_FACTOR };
        }

        allocator: *std.mem.Allocator,
        root: *Node,

        pub fn init(comptime allocator: *std.mem.Allocator) !Self {
            var root = try allocator.create(Node);
            errdefer self.allocator.destroy(root);

            root.* = emptyBranch();
            return Self{ .allocator = allocator, .root = root };
        }

        pub fn deinit(self: *Self) void {
            const root = self.root;
            self.root.* = undefined;
            self.allocator.destroy(root);
            self.* = undefined;
        }

        pub fn store(self: *Self, block: Block) Hash {
            return 0;
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

test "walk" {
    inline for (.{ 10, 12, 15 }) |BLOCK_POWER| {
        const Map = AutoMap(BLOCK_POWER);
        std.debug.print("\nBLOCK_POWER = {}\n", .{BLOCK_POWER});
        std.debug.print("Map.BLOCK_SIZE = {}\n", .{Map.BLOCK_SIZE});
        std.debug.print("Map.BRANCH_POWER = {}\n", .{Map.BRANCH_POWER});
        // std.debug.print("Map.BRANCH_FACTOR = {}\n", .{Map.BRANCH_FACTOR});
        // std.debug.print("@sizeOf(Map.Hash) = {}\n", .{@sizeOf(Map.Hash)});
        // std.debug.print("@sizeOf(Map.Block) = {}\n", .{@sizeOf(Map.Block)});
        // std.debug.print("@sizeOf(Map.Branch) = {}\n", .{@sizeOf(Map.Branch)});
        // std.debug.print("@sizeOf(Map.Leaf) = {}\n", .{@sizeOf(Map.Leaf)});
        // std.debug.print("@sizeOf(?*Map.Node) = {}\n", .{@sizeOf(?*Map.Node)});

        const hash: Hash = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        comptime var index: u32 = 0;
        std.debug.print("BRANCH_POWER = {}\n", .{Map.BRANCH_POWER});
        inline while (index * Map.BRANCH_POWER < @bitSizeOf(@TypeOf(hash))) {
            const bits = Map.getBitSlice(hash, index);
            std.debug.print("index = {} bits = 0x{x}\n", .{ index, bits });
            index += 1;
        }
    }
}

// pub fn main() anyerror!void {

//     std.log.info("All your codebase are belong to us.", .{});
// }
