// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

//!
//! move gen baby
//!

const std = @import("std");

const Position = @import("Position.zig");
const Coordinate = @import("Coordinate.zig");
const Move = @import("Move.zig");
const Piece = @import("Piece.zig");

const Affiliation = Piece.Affiliation;
const Class = Piece.Class;
const Direction = Coordinate.Direction;
const DirectionalIterator = Coordinate.DirectionalIterator;

const bishop_directions = [_]Direction{ .northeast, .northwest, .southeast, .southwest };
const rook_directions = [_]Direction{ .north, .south, .east, .west };
const queen_directions = bishop_directions ++ rook_directions;

/// iterates over psuedo legal moves from a single piece
pub const MoveIterator = struct {
    position: *const Position,
    coord: Coordinate,
    piece: Piece,
    i: usize,
    at: Coordinate,

    /// create a `MoveIterator`
    /// assumes `position` will be in scope for the lifetime
    /// of returned `MoveIterator`
    /// expects `coord` to point to a non-empty square in `position`
    pub fn init(position: *const Position, coord: Coordinate) error{no_piece}!MoveIterator {
        const piece = position.at(coord);
        if (piece.isEmpty()) return error.no_piece;
        return .{
            .position = position,
            .coord = coord,
            .piece = piece,
            .i = 0,
            .at = coord,
        };
    }

    /// return the next psuedo legal move
    /// return null if no more moves
    pub fn next(this: *MoveIterator) ?Move {
        return switch (this.piece.class().?) {
            .pawn => this.nextPawn(),
            .knight => this.nextKnight(),
            .bishop => this.nextSliding(&bishop_directions),
            .rook => this.nextSliding(&rook_directions),
            .queen => this.nextSliding(&queen_directions),
            .king => this.nextKing(),
        };
    }

    /// next() implementation for sliding pieces
    fn nextSliding(this: *MoveIterator, dirs: []const Direction) ?Move {
        while (true) {
            if (this.i >= dirs.len)
                return null;
            if (this.at.offsettedDir(dirs[this.i], 1)) |at| {
                const piece = this.position.at(at);
                if (piece.isEmpty()) {
                    this.at = at;
                    return Move.init(this.coord, at, .none);
                }
                this.at = this.coord;
                this.i += 1;
                if (piece.affiliation().? != this.piece.affiliation().?)
                    return Move.init(this.coord, at, .none);
            } else {
                this.at = this.coord;
                this.i += 1;
            }
        }
    }

    /// next() implementation for knights
    fn nextKnight(this: *MoveIterator) ?Move {
        while (true) : (this.i += 1) {
            if (switch (this.i) {
                0 => this.coord.offsetted(-2, 1),
                1 => this.coord.offsetted(-1, 2),
                2 => this.coord.offsetted(1, 2),
                3 => this.coord.offsetted(2, 1),
                4 => this.coord.offsetted(2, -1),
                5 => this.coord.offsetted(1, -2),
                6 => this.coord.offsetted(-1, -2),
                7 => this.coord.offsetted(-2, -1),
                else => return null,
            }) |at| {
                const piece = this.position.at(at);
                if (piece.isEmpty() or piece.affiliation().? != this.piece.affiliation().?) {
                    this.i += 1;
                    return Move.init(this.coord, at, .none);
                }
            }
        }
    }

    /// next() implementation for kings
    fn nextKing(this: *MoveIterator) ?Move {
        const offsets = [_]i8{ -9, -8, -7, -1, 1, 7, 8, 9 };
        const affiliation = this.piece.affiliation().?;

        if (this.i > offsets.len + 1)
            return null;

        while (this.i < offsets.len) {
            const at = this.coord.offsettedVal(offsets[this.i]);
            this.i += 1;
            if (at == null) continue;
            const piece = this.position.at(at.?);
            if (piece.isEmpty() or piece.affiliation().? != affiliation)
                return Move.init(this.coord, at.?, .none);
        }

        // can only castle from starting pos
        if (this.coord.value != affiliation.kingCoord().value)
            return null;

        if (this.i == offsets.len) {
            // king side castle
            this.i += 1;
            if (this.position.meta.castleKing(affiliation) and
                !this.canCastle(affiliation, .kingside))
            {
                return Move.init(this.coord, affiliation.kingCastleDest(), .castle);
            }
        } else if (this.i == offsets.len + 1) {
            // queenside castle
            this.i += 1;
            if (this.position.meta.castleQueen(affiliation) and
                !this.canCastle(affiliation, .queenside))
            {
                return Move.init(this.coord, affiliation.queenCastleDest(), .castle);
            }
        }

        return null;
    }

    /// next() implementation for pawns
    fn nextPawn(this: *MoveIterator) ?Move {
        const affiliation = this.piece.affiliation().?;
        const single_push_dest = this.coord.offsettedDir(affiliation.direction(), 1);
        const double_push_dest = this.coord.offsettedDir(affiliation.direction(), 2);
        const west_cap_dest = this.coord.offsettedDir(affiliation.direction().toWest(), 1);
        const east_cap_dest = this.coord.offsettedDir(affiliation.direction().toEast(), 1);
        const west_enpassant_target = this.coord.offsettedDir(.west, 1);
        const east_enpassant_target = this.coord.offsettedDir(.east, 1);

        //
        // for pawn moves `this.i` stores two pieces of data
        // the low 32 bits are use to keep track of the base move
        // sans promotion, and the high 32 bits are used to keep
        // track of the promotion flag. (We need to output 4 moves
        // for every move that result in a promotion, one for each
        // promotion class. Every pawn move made from the respective 7th
        // rank results in promotion)
        //

        // base move without promotions
        var move = while (true) : (this.i += 1) {
            switch (this.low32()) {
                // single push
                0 => if (this.position.at(single_push_dest.?).isEmpty())
                    break Move.init(this.coord, single_push_dest.?, .none),

                // double push
                1 => if (this.coord.getRank() == affiliation.secondRank() and
                    this.position.at(single_push_dest.?).isEmpty() and
                    this.position.at(double_push_dest.?).isEmpty())
                {
                    this.i += 1;
                    return Move.init(this.coord, double_push_dest.?, .pawn_double_push);
                },

                // west capture
                2 => if (this.coord.getFile() != Coordinate.File.file_a and
                    this.position.at(west_cap_dest.?).isAffiliated(affiliation.opponent()))
                    break Move.init(this.coord, west_cap_dest.?, .none),

                // east capture
                3 => if (this.coord.getFile() != Coordinate.File.file_h and
                    this.position.at(east_cap_dest.?).isAffiliated(affiliation.opponent()))
                    break Move.init(this.coord, east_cap_dest.?, .none),

                // west en passant
                4 => if (this.coord.getFile() != Coordinate.File.file_a and
                    this.position.meta.enpassantFile() == this.coord.getFile().west().? and
                    this.position.at(west_enpassant_target.?).isAffiliated(affiliation.opponent()))
                {
                    this.i += 1;
                    return Move.init(this.coord, west_cap_dest.?, .enpassant_capture);
                },

                // east en passant
                5 => if (this.coord.getFile() != Coordinate.File.file_h and
                    this.position.meta.enpassantFile() == this.coord.getFile().east().? and
                    this.position.at(east_enpassant_target.?).isAffiliated(affiliation.opponent()))
                {
                    this.i += 1;
                    return Move.init(this.coord, east_cap_dest.?, .enpassant_capture);
                },

                else => return null,
            }
        };

        // promotions
        if (this.coord.getRank() == affiliation.opponent().secondRank()) {
            const promotion_flag = @intToEnum(Move.Flag, @intCast(u4, this.high32() + 1));
            this.i += 0x100000000; // inc high 32
            if (this.high32() >= 4) {
                this.i &= 0x00000000ffffffff; // clear high 32
                this.i += 1; // inc low 32
            }
            move.setFlag(promotion_flag);
            return move;
        } else {
            this.i += 1;
            return move;
        }
    }

    /// determine if the affiliated king can castle in the geven direction
    /// ensures all squres between king and rook are empty and not under attack
    fn canCastle(this: MoveIterator, affiliation: Affiliation, side: enum(usize) { kingside, queenside }) bool {
        // cannot castle through pieces
        const dir: Direction = if (side == .kingside) .east else .west;
        const count: i8 = if (side == .kingside) 2 else 3;
        var dir_iter = DirectionalIterator.init(affiliation.kingCoord(), dir, count);
        while (dir_iter.next()) |coord| {
            if (!this.position.at(coord).isEmpty())
                return false;
        }

        const target_coords = [_][]const Coordinate{
            // whiteking
            &[_]Coordinate{ Coordinate.e1, Coordinate.f1, Coordinate.g1 },
            // whitequeen
            &[_]Coordinate{ Coordinate.e1, Coordinate.d1, Coordinate.c1 },
            // blackking
            &[_]Coordinate{ Coordinate.e8, Coordinate.f8, Coordinate.g8 },
            // blackqueen
            &[_]Coordinate{ Coordinate.e8, Coordinate.d8, Coordinate.c8 },
        };
        const index = @enumToInt(side) + @intCast(usize, @enumToInt(affiliation)) * 2;
        const targets = target_coords[index];

        // cannot castle through check
        const pieces = this.position.piecesFromAffiliation(affiliation);
        var piece_iter = pieces.iterator();
        while (piece_iter.next()) |coord| {
            var move_iter = MoveIterator.init(this.position, coord) catch unreachable;
            while (move_iter.next()) |move| {
                for (targets) |target| {
                    if (move.dest().value == target.value)
                        return false;
                }
            }
        }

        return true;
    }

    /// returns the least significant 32 bits from `MoveIterator.i`
    fn low32(this: MoveIterator) u32 {
        return @intCast(u32, this.i & 0x00000000ffffffff);
    }

    /// returns the most significant 32 bits from `MoveIterator.i`
    fn high32(this: MoveIterator) u32 {
        return @intCast(u32, (this.i & 0xffffffff00000000) >> 32);
    }
};

/// generates possible moves for the given affiliation
/// reults are written into `buffer`, if space in `buffer`
/// is exahstid before all moves have been written,
/// return `error.buffer_overflow`
pub fn generateMoves(position: Position, affiliation: Affiliation, buffer: []Move) error{buffer_overflow}![]Move {
    _ = affiliation;
    _ = position;
    return buffer[0..0];
}

test "movegen - queen" {
    const fen = "1K6/8/8/3Q4/8/2P5/8/qk6 w - - 0 1";
    var black_moves = [_]Move{
        Move.init(Coordinate.a1, Coordinate.b2, .none),
        Move.init(Coordinate.a1, Coordinate.c3, .none),
        Move.init(Coordinate.a1, Coordinate.a2, .none),
        Move.init(Coordinate.a1, Coordinate.a3, .none),
        Move.init(Coordinate.a1, Coordinate.a4, .none),
        Move.init(Coordinate.a1, Coordinate.a5, .none),
        Move.init(Coordinate.a1, Coordinate.a6, .none),
        Move.init(Coordinate.a1, Coordinate.a7, .none),
        Move.init(Coordinate.a1, Coordinate.a8, .none),
    };
    var white_moves = [_]Move{
        Move.init(Coordinate.d5, Coordinate.c5, .none),
        Move.init(Coordinate.d5, Coordinate.b5, .none),
        Move.init(Coordinate.d5, Coordinate.a5, .none),
        Move.init(Coordinate.d5, Coordinate.c6, .none),
        Move.init(Coordinate.d5, Coordinate.b7, .none),
        Move.init(Coordinate.d5, Coordinate.a8, .none),
        Move.init(Coordinate.d5, Coordinate.d6, .none),
        Move.init(Coordinate.d5, Coordinate.d7, .none),
        Move.init(Coordinate.d5, Coordinate.d8, .none),
        Move.init(Coordinate.d5, Coordinate.e6, .none),
        Move.init(Coordinate.d5, Coordinate.f7, .none),
        Move.init(Coordinate.d5, Coordinate.g8, .none),
        Move.init(Coordinate.d5, Coordinate.e5, .none),
        Move.init(Coordinate.d5, Coordinate.f5, .none),
        Move.init(Coordinate.d5, Coordinate.g5, .none),
        Move.init(Coordinate.d5, Coordinate.h5, .none),
        Move.init(Coordinate.d5, Coordinate.e4, .none),
        Move.init(Coordinate.d5, Coordinate.f3, .none),
        Move.init(Coordinate.d5, Coordinate.g2, .none),
        Move.init(Coordinate.d5, Coordinate.h1, .none),
        Move.init(Coordinate.d5, Coordinate.d4, .none),
        Move.init(Coordinate.d5, Coordinate.d3, .none),
        Move.init(Coordinate.d5, Coordinate.d2, .none),
        Move.init(Coordinate.d5, Coordinate.d1, .none),
        Move.init(Coordinate.d5, Coordinate.c4, .none),
        Move.init(Coordinate.d5, Coordinate.b3, .none),
        Move.init(Coordinate.d5, Coordinate.a2, .none),
    };
    try expectMoves(fen, Coordinate.a1, &black_moves, black_moves.len);
    try expectMoves(fen, Coordinate.d5, &white_moves, white_moves.len);
}

test "movegen - knight" {
    const fen = "n7/8/1k6/8/3N4/1r6/8/7K w - - 0 1";
    var black_moves = [_]Move{Move.init(Coordinate.a8, Coordinate.c7, .none)};
    var white_moves = [_]Move{
        Move.init(Coordinate.d4, Coordinate.b3, .none),
        Move.init(Coordinate.d4, Coordinate.c2, .none),
        Move.init(Coordinate.d4, Coordinate.e2, .none),
        Move.init(Coordinate.d4, Coordinate.f3, .none),
        Move.init(Coordinate.d4, Coordinate.f5, .none),
        Move.init(Coordinate.d4, Coordinate.e6, .none),
        Move.init(Coordinate.d4, Coordinate.c6, .none),
        Move.init(Coordinate.d4, Coordinate.b5, .none),
    };
    try expectMoves(fen, Coordinate.a8, &black_moves, black_moves.len);
    try expectMoves(fen, Coordinate.d4, &white_moves, white_moves.len);
}

test "movegen - pawn - double push" {
    var expected_moves = [_]Move{
        Move.init(Coordinate.d2, Coordinate.d3, .none),
        Move.init(Coordinate.d2, Coordinate.d4, .pawn_double_push),
    };
    try expectMoves("r6k/1P6/8/8/1pP5/8/3P4/7K w - c3 0 1", Coordinate.d2, &expected_moves, expected_moves.len);
}

test "movegen - pawn - single push" {
    const fen = "r6k/1P6/8/8/1pP5/3p4/3P4/7K w - c3 0 1";
    var c4_moves = [_]Move{
        Move.init(Coordinate.c4, Coordinate.c5, .none),
    };
    var d2_moves = [_]Move{};
    try expectMoves(fen, Coordinate.c4, &c4_moves, c4_moves.len);
    try expectMoves(fen, Coordinate.d2, &d2_moves, d2_moves.len);
}

test "movegen - pawn - enpassant" {
    var expected_moves = [_]Move{
        Move.init(Coordinate.b4, Coordinate.b3, .none),
        Move.init(Coordinate.b4, Coordinate.c3, .enpassant_capture),
    };
    try expectMoves("r6k/1P6/8/8/1pP5/8/3P4/7K w - c3 0 1", Coordinate.b4, &expected_moves, expected_moves.len);
}

test "movegen - pawn - promotion" {
    var expected_moves = [_]Move{
        Move.init(Coordinate.b7, Coordinate.b8, .promote_queen),
        Move.init(Coordinate.b7, Coordinate.b8, .promote_rook),
        Move.init(Coordinate.b7, Coordinate.b8, .promote_bishop),
        Move.init(Coordinate.b7, Coordinate.b8, .promote_knight),
        Move.init(Coordinate.b7, Coordinate.a8, .promote_queen),
        Move.init(Coordinate.b7, Coordinate.a8, .promote_rook),
        Move.init(Coordinate.b7, Coordinate.a8, .promote_bishop),
        Move.init(Coordinate.b7, Coordinate.a8, .promote_knight),
    };
    try expectMoves("r6k/1P6/8/8/1pP5/8/3P4/7K w - c3 0 1", Coordinate.b7, &expected_moves, expected_moves.len);
}

/// tests move gen correctly generates `expected_moves` for piece at `coord`
/// in position defined by `position_fen`
fn expectMoves(position_fen: []const u8, coord: Coordinate, expected_moves: []Move, comptime count: usize) !void {
    try std.testing.expectEqual(count, expected_moves.len);

    const position = try Position.fromFen(position_fen);
    var iter = try MoveIterator.init(&position, coord);
    var actual: [count]Move = undefined;
    var i: usize = 0;
    while (iter.next()) |move| {
        if (i >= count) {
            std.debug.print("move count exceeded expected count of {}\n", .{count});
            return error.TestExpectMoves;
        }
        actual[i] = move;
        i += 1;
    }
    try expectEqualMovesets(expected_moves, actual[0..i]);
}

/// compares two slices for equality an a order insensitive maner
fn expectEqualMovesets(expected: []Move, actual: []Move) !void {
    if (expected.len != actual.len) {
        std.debug.print("move counts differ, expected {}, found {}\n", .{ expected.len, actual.len });
        return error.TestExpectEqualMovesets;
    }
    std.sort.sort(Move, expected, {}, lessThanMove);
    std.sort.sort(Move, actual, {}, lessThanMove);
    try std.testing.expectEqualSlices(Move, expected, actual);
}

/// compare moves for ordering
fn lessThanMove(_: void, lhs: Move, rhs: Move) bool {
    return lhs.bits.bits < rhs.bits.bits;
}
