// ********************************************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const types = @import("types.zig");

const Board = @This();
const Piece = @import("Piece.zig");
const Notation = @import("Notation.zig");

const Class = Piece.Class;
const Affiliation = Piece.Affiliation;
const Square = types.Square;
const Coordinate = types.Coordinate;
const Move = types.Move;
const MoveResult = types.MoveResult;

/// the 64 squares of a chess board laid out a rank 1 to 8 file a to h
/// see Coordinate.to1d and Coordinate.from_1d for mapping
squares: [64]Square,

/// standard chess starting position
const starting_position: [64]Square = blk_starting_position: {
    var squares: [64]Square = [1]Square{Square.empty()} ** 64;
    // helper to get pieces on the back ranks
    const back_rank = struct {
        const sequence: [8]Class = blk_sequence: {
            var classes: [8]Class = undefined;
            // back rank pieces from a to h
            classes[0] = .rook;
            classes[1] = .knight;
            classes[2] = .bishop;
            classes[3] = .queen;
            classes[4] = .king;
            classes[5] = .bishop;
            classes[6] = .knight;
            classes[7] = .rook;
            break :blk_sequence classes;
        };
        /// return white piece on back rank file `file`
        pub fn white(file: u8) Square {
            return Square.init(Piece.init(sequence[file], .white));
        }
        /// return black piece on back rank file `file`
        pub fn black(file: u8) Square {
            return Square.init(Piece.init(sequence[file], .black));
        }
    };
    // iterate over files a to h (0 to 7)
    const white_pawn = Square.init(Piece.init(.pawn, .white));
    const black_pawn = Square.init(Piece.init(.pawn, .black));
    var file = 0;
    while (file < 8) : (file += 1) {
        // back rank
        squares[Coordinate.init(file, 0).to1d()] = back_rank.white(file);
        squares[Coordinate.init(file, 7).to1d()] = back_rank.black(file);
        // pawns
        squares[Coordinate.init(file, 1).to1d()] = white_pawn;
        squares[Coordinate.init(file, 6).to1d()] = black_pawn;
    }
    break :blk_starting_position squares;
};

/// create an empty board
pub fn initEmpty() Board {
    return .{
        .squares = [1]Square{Square.empty()} ** 64,
    };
}

/// create a board with standard chess starting position
pub fn init() Board {
    return .{
        .squares = starting_position,
    };
}

/// return piece at coord, null if no piece
pub fn at(board: Board, pos: Coordinate) ?Piece {
    return board.squares[pos.to1d()].piece();
}

/// spawn piece at given coord
pub fn spawn(board: *Board, piece: Piece, pos: Coordinate) void {
    board.squares[pos.to1d()] = Square.init(piece);
}

/// moves a pices to a different square, does no validation
pub fn makeMove(board: *Board, move: Move) MoveResult {
    if (board.at(move.location)) |piece| {
        std.debug.assert(piece.bits == move.piece.bits);
        board.squares[move.location.to1d()] = Square.empty();
        board.squares[move.destination.to1d()] = Square.init(move.piece);
        return .ok;
    } else return .no_such_piece;
}

/// submit move, move to be made pending validation
/// uses standard chess notation (https://en.wikipedia.org/wiki/Algebraic_notation_(chess))
pub fn submitMove(board: *Board, affiliation: Affiliation, move_notation: []const u8) MoveResult {
    const move = Notation.parse(move_notation) orelse return .bad_notation;

    if (board.at(move.destination)) |dest_piece| {
        if (dest_piece.affiliation() == affiliation)
            return .blocked;
    }

    var buffer: [32]usize = undefined;
    const results = board.query(&buffer, .{
        .class = move.class,
        .affiliation = affiliation,
        .target_coord = move.destination,
        .source_file = move.source_file,
        .source_rank = move.source_rank,
    });

    if (results.len > 1)
        return .ambiguous_piece;
    if (results.len == 0)
        return .no_visibility;

    // TODO: checks and mates

    return board.makeMove(.{
        .piece = Piece.init(move.class, affiliation),
        .location = Coordinate.from1d(results[0]),
        .destination = move.destination,
    });
}

/// options for making querys with Board.query()
pub const Query = struct {
    /// search for pieces of this class
    class: ?Class = null,
    /// search for pieces of this affiliation
    affiliation: ?Affiliation = null,
    /// search for pieces that can move here
    target_coord: ?Coordinate = null,
    /// search for pieces that can capture on target_coord
    /// needed because pawns capture differently than they move
    attacking: ?bool = null,
    /// search for pieces on this file
    source_file: ?i8 = null,
    /// search for pieces on this rank
    source_rank: ?i8 = null,
};

/// query's the board of pieces
/// /param buffer buffer to write results to
/// /param query_expr constraints to search for
/// /returns slice into `buffer` containing 1d coordinates of matching pieces
pub fn query(board: Board, buffer: *[32]usize, query_expr: Query) []const usize {
    var count: usize = 0;

    // write initial pieces with expected affiliation
    for (board.squares) |square, i| {
        if (square.piece()) |piece| {
            if (query_expr.affiliation) |affiliation| {
                if (piece.affiliation() == affiliation) {
                    buffer[count] = i;
                    count += 1;
                }
            } else {
                buffer[count] = i;
                count += 1;
            }
        }
    }

    // filter with expected class
    if (query_expr.class) |class| {
        var i: usize = 0;
        while (i < count) {
            const piece = board.squares[buffer[i]].piece().?;
            if (piece.class() != class) {
                // swap and pop delete
                buffer[i] = buffer[count - 1];
                count -= 1;
            } else i += 1;
        }
    }

    // filter with target_coord
    if (query_expr.target_coord) |coord| {
        var i: usize = 0;
        while (i < count) {
            if (!board.hasVisability(buffer[i], coord.to1d(), query_expr.attacking orelse false)) {
                // swap and pop delete
                buffer[i] = buffer[count - 1];
                count -= 1;
            } else i += 1;
        }
    }

    // filter with source_file
    if (query_expr.source_file) |file| {
        var i: usize = 0;
        while (i < count) {
            if (Coordinate.from1d(buffer[i]).file != file) {
                // swap and pop delete
                buffer[i] = buffer[count - 1];
                count -= 1;
            } else i += 1;
        }
    }

    // filter with source_rank
    if (query_expr.source_rank) |rank| {
        var i: usize = 0;
        while (i < count) {
            if (Coordinate.from1d(buffer[i]).rank != rank) {
                // swap and pop delete
                buffer[i] = buffer[count - 1];
                count -= 1;
            } else i += 1;
        }
    }

    return buffer[0..count];
}

/// validate that the piece on source square can move to dest square
/// does not consider checks
/// can_capture ensures that the source piece can capture on dest, important for pawns
/// takes source and dest as 1d coordinates
fn hasVisability(board: Board, source: usize, dest: usize, attacking: bool) bool {
    std.debug.assert(source < board.squares.len);
    std.debug.assert(dest < board.squares.len);
    if (dest == source)
        return false;
    if (board.squares[source].piece()) |piece| {
        const class = piece.class();
        const affiliation = piece.affiliation();
        const source2d = Coordinate.from1d(source);
        const dest2d = Coordinate.from1d(dest);
        switch (class) {
            .pawn => {
                // TODO: en passant
                if (attacking) {
                    return (dest2d.rank == source2d.rank + affiliation.direction()) and
                        (dest2d.file == source2d.file + 1 or dest2d.file == source2d.file + 1);
                } else {
                    // double push
                    if (dest2d.rank == affiliation.doublePushRank() and source2d.rank == affiliation.secondRank()) {
                        return dest2d.file == source2d.file and
                            board.at(source2d.offsetted(0, affiliation.direction())) == null and
                            board.at(dest2d) == null;
                    }
                    // single push
                    if (dest2d.file == source2d.file and dest2d.rank == source2d.rank + affiliation.direction())
                        return board.at(dest2d) == null;
                    // captures
                    if ((dest2d.file == source2d.file + 1 or dest2d.file == source2d.file - 1) and dest2d.rank == source2d.rank + affiliation.direction())
                        return board.at(dest2d) != null and board.at(dest2d).?.affiliation() == affiliation.opponent();
                    return false;
                }
            },
            .knight => {
                const rank_diff: i8 = abs(dest2d.rank - source2d.rank);
                const file_diff: i8 = abs(dest2d.file - source2d.file);
                return (rank_diff == 2 and file_diff == 1) or (rank_diff == 1 and file_diff == 2);
            },
            .bishop => {
                const rank_diff = dest2d.rank - source2d.rank;
                const file_diff = dest2d.file - source2d.file;
                if (abs(rank_diff) != abs(file_diff))
                    return false;
                return board.ensureEmpty(source2d, dest2d);
            },
            .rook => {
                if (dest2d.rank != source2d.rank and dest2d.file != source2d.file)
                    return false;
                return board.ensureEmpty(source2d, dest2d);
            },
            .queen => {
                const rank_diff = dest2d.rank - source2d.rank;
                const file_diff = dest2d.file - source2d.file;
                if (dest2d.rank != source2d.rank and dest2d.file != source2d.file and
                    abs(rank_diff) != abs(file_diff))
                    return false;
                return board.ensureEmpty(source2d, dest2d);
            },
            .king => {
                if (dest2d.file > source2d.file + 1 or
                    dest2d.file < source2d.file - 1 or
                    dest2d.rank > source2d.rank + 1 or
                    dest2d.rank < source2d.rank - 1)
                    return false
                else
                    return true;
            },
        }
    }
    return false;
}

/// ensures all squares between source and dest are empty
fn ensureEmpty(board: Board, source: Coordinate, dest: Coordinate) bool {
    const rank_diff = dest.rank - source.rank;
    const file_diff = dest.file - source.file;
    const length = std.math.sqrt(@intCast(u8, rank_diff * rank_diff + file_diff * file_diff));
    const rank_delta = std.math.clamp(div(rank_diff, length), -1, 1);
    const file_delta = std.math.clamp(div(file_diff, length), -1, 1);
    var coord = source;
    coord.rank += rank_delta;
    coord.file += file_delta;
    while (coord.valid() and coord.to1d() != dest.to1d()) {
        if (board.squares[coord.to1d()].piece()) |_|
            return false;
        coord.rank += rank_delta;
        coord.file += file_delta;
    }
    return true;
}

/// divide n / d rounding away from zero
fn div(n: i8, d: i8) i8 {
    const quotiant = @intToFloat(f32, n) / @intToFloat(f32, d);
    const sign = std.math.sign(quotiant);
    const val = @fabs(quotiant);
    return @floatToInt(i8, @ceil(val) * sign);
}

/// helper for absolute values
fn abs(val: i8) i8 {
    return std.math.absInt(val) catch std.math.maxInt(i8);
}
