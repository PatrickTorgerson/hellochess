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

const MetaState = struct {
    in_check: bool = false,
    king_has_moved: bool = false,
    h_rook_has_moved: bool = false,
    a_rook_has_moved: bool = false,
    king_coord: Coordinate = Coordinate.from1d(0),
};

/// the 64 squares of a chess board laid out a rank 1 to 8 file a to h
/// see Coordinate.to1d and Coordinate.from_1d for mapping
squares: [64]Square,
white_state: MetaState,
black_state: MetaState,

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

/// create an empty board, with onlt kings
pub fn initEmpty() Board {
    var this = Board{
        .squares = [1]Square{Square.empty()} ** 64,
        .white_state = .{
            .king_coord = Affiliation.white.kingCoord(),
            .h_rook_has_moved = true,
            .a_rook_has_moved = true,
        },
        .black_state = .{
            .king_coord = Affiliation.black.kingCoord(),
            .h_rook_has_moved = true,
            .a_rook_has_moved = true,
        },
    };
    this.squares[Affiliation.white.kingCoord().to1d()] = Square.init(Piece.init(.king, .white));
    this.squares[Affiliation.black.kingCoord().to1d()] = Square.init(Piece.init(.king, .black));
    return this;
}

/// create a board with standard chess starting position
pub fn init() Board {
    return .{
        .squares = starting_position,
        .white_state = .{ .king_coord = Affiliation.white.kingCoord() },
        .black_state = .{ .king_coord = Affiliation.black.kingCoord() },
    };
}

/// return a duplicate of board
pub fn dupe(board: Board) Board {
    return .{
        .squares = board.squares,
        .white_state = board.white_state,
        .black_state = board.black_state,
    };
}

/// return piece at coord, null if no piece
pub fn at(board: Board, pos: Coordinate) ?Piece {
    return board.squares[pos.to1d()].piece();
}

/// spawn piece at given coord pending validation
pub fn spawn(board: *Board, piece: Piece, pos: Coordinate) MoveResult {
    const move = Move{
        .piece = piece,
        .destination = pos,
    };
    var state = board.getMetaState(piece.affiliation());
    var buffer: [32]usize = undefined;
    if (state.in_check) {
        const checkers = board.query(&buffer, .{
            .affiliation = piece.affiliation().opponent(),
            .target_coord = state.king_coord,
            .hypothetical_move = move,
            .attacking = true,
        });
        if (checkers.len > 0)
            return .in_check
        else
            state.in_check = false;
    }
    return board.makeMove(move);
}

/// makes a move, no validation, no searching for checks or mates
/// returns null when move result is ok but potentially a check or mate
pub fn forceMove(board: *Board, move: Move) ?MoveResult {
    var state = board.getMetaState(move.piece.affiliation());
    if (move.castle_kingside) |kingside| {
        std.debug.assert(move.piece.class() == .king); // piece must be king when castling
        const king_delta: i8 = if (kingside) 2 else -2;
        const rook_delta: i8 = if (kingside) -2 else 3;
        const affiliation = move.piece.affiliation();

        if (state.king_has_moved)
            return .castle_king_moved;
        if (kingside and state.h_rook_has_moved)
            return .castle_rook_moved;
        if (!kingside and state.a_rook_has_moved)
            return .castle_rook_moved;

        const rook_source_coord = if (kingside)
            affiliation.hRookCoord()
        else
            affiliation.aRookCoord();

        board.squares[state.king_coord.to1d()] = Square.empty();
        board.squares[rook_source_coord.to1d()] = Square.empty();

        state.king_coord = state.king_coord.offsetted(king_delta, 0);

        board.squares[state.king_coord.to1d()] = Square.init(move.piece);
        board.squares[rook_source_coord.offsetted(rook_delta, 0).to1d()] = Square.init(Piece.init(.rook, affiliation));

        state.king_has_moved = true;
        if (kingside)
            state.h_rook_has_moved = true
        else
            state.a_rook_has_moved = true;
        return null;
    } else if (move.location == null) {
        // spawn piece
        if (move.destination.to1d() == state.king_coord.to1d())
            return .no_visibility;
        if (move.destination.to1d() == board.getMetaState(move.piece.affiliation().opponent()).king_coord.to1d())
            return .no_visibility;
        board.squares[move.destination.to1d()] = Square.init(move.piece);
        if (move.piece.class() == .king) {
            // there can only be one
            board.squares[state.king_coord.to1d()] = Square.empty();
            state.king_coord = move.destination;
            if (move.destination.to1d() == move.piece.affiliation().kingCoord().to1d())
                state.king_has_moved = false
            else
                state.king_has_moved = true;
        } else if (move.piece.class() == .rook) {
            // spawning rooks in their standard starting pos
            // counts as them no moving, usefull for testing castling
            if (move.destination.to1d() == move.piece.affiliation().aRookCoord().to1d())
                state.a_rook_has_moved = false
            else if (move.destination.to1d() == move.piece.affiliation().hRookCoord().to1d())
                state.h_rook_has_moved = false;
        }
        return null;
    } else if (board.at(move.location.?)) |piece| {
        std.debug.assert(piece.bits == move.piece.bits);
        board.squares[move.location.?.to1d()] = Square.empty();
        board.squares[move.destination.to1d()] = Square.init(move.piece);
        if (piece.class() == .king) {
            state.king_coord = move.destination;
            state.king_has_moved = true;
        } else if (piece.class() == .rook) {
            if (move.location.?.to1d() == piece.affiliation().hRookCoord().to1d() and !state.h_rook_has_moved) {
                state.h_rook_has_moved = true;
            }
            if (move.location.?.to1d() == piece.affiliation().aRookCoord().to1d() and !state.a_rook_has_moved) {
                state.a_rook_has_moved = true;
            }
        }
        return null;
    } else return .no_such_piece;
}

/// moves a pices to a different square, does no validation
pub fn makeMove(board: *Board, move: Move) MoveResult {
    if (board.forceMove(move)) |result|
        return result
    else
        return board.checksAndMates(move.piece.affiliation().opponent());
}

/// return meta state for given affiliation
pub fn getMetaState(board: *Board, affiliation: Affiliation) *MetaState {
    return switch (affiliation) {
        .white => &board.white_state,
        .black => &board.black_state,
    };
}

/// submit move, move to be made pending validation
/// uses standard chess notation (https://en.wikipedia.org/wiki/Algebraic_notation_(chess))
pub fn submitMove(board: *Board, affiliation: Affiliation, move_notation: []const u8) MoveResult {
    const notation = Notation.parse(move_notation) orelse return .bad_notation;

    if (notation.castle_kingside) |castle_kingside| {
        return board.castle(affiliation, castle_kingside);
    }

    if (board.at(notation.destination)) |dest_piece| {
        if (dest_piece.affiliation() == affiliation)
            return .blocked;
    }

    var buffer: [32]usize = undefined;
    const results = board.query(&buffer, .{
        .class = notation.class,
        .affiliation = affiliation,
        .target_coord = notation.destination,
        .source_file = notation.source_file,
        .source_rank = notation.source_rank,
    });

    if (results.len > 1)
        return .ambiguous_piece;
    if (results.len == 0)
        return .no_visibility;

    const move = Move{
        .piece = Piece.init(notation.class, affiliation),
        .location = Coordinate.from1d(results[0]),
        .destination = notation.destination,
    };

    var state = board.getMetaState(affiliation);
    if (move.piece.class() == .king) {
        const attackers = board.query(&buffer, .{
            .affiliation = affiliation.opponent(),
            .target_coord = notation.destination,
            .attacking = true,
            .hypothetical_move = move,
        });
        if (attackers.len > 0)
            return if (state.in_check) .in_check else .enters_check;
    } else {
        const checkers = board.query(&buffer, .{
            .affiliation = affiliation.opponent(),
            .target_coord = state.king_coord,
            .hypothetical_move = move,
            .attacking = true,
        });
        if (checkers.len > 0)
            return if (state.in_check) .in_check else .enters_check;
    }

    state.in_check = false;

    return board.makeMove(move);
}

/// attempt to castle, pending validation
pub fn castle(board: *Board, affiliation: Affiliation, kingside: bool) MoveResult {
    const state = board.getMetaState(affiliation);
    if (state.in_check)
        return .castle_in_check;
    if (state.king_has_moved)
        return .castle_king_moved;
    if (kingside and state.h_rook_has_moved)
        return .castle_rook_moved;
    if (!kingside and state.a_rook_has_moved)
        return .castle_rook_moved;

    var buffer: [32]usize = undefined;
    const file_delta: i8 = if (kingside) 3 else -3;
    var iter = DirectionalIterator.init(state.king_coord, state.king_coord.offsetted(file_delta, 0));
    while (iter.next()) |coord| {
        if (board.at(coord) != null)
            return .blocked;
        const attackers = board.query(&buffer, .{
            .affiliation = affiliation.opponent(),
            .attacking = true,
            .target_coord = coord,
        });
        if (attackers.len > 0)
            return .castle_through_check;
    }

    return board.makeMove(.{
        .piece = Piece.init(.king, affiliation),
        .castle_kingside = kingside,
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
    /// query board position as if this move was made
    hypothetical_move: ?Move = null,
    /// exclude kings from results
    exclude_king: bool = false,
};

/// query's the board of pieces
/// /param buffer buffer to write results to
/// /param query_expr constraints to search for
/// /returns slice into `buffer` containing 1d coordinates of matching pieces
pub fn query(board: Board, buffer: *[32]usize, query_expr: Query) []const usize {
    var count: usize = 0;

    var board_dupe = board.dupe();
    if (query_expr.hypothetical_move) |move|
        _ = board_dupe.forceMove(move);

    // write initial pieces with expected affiliation
    for (board_dupe.squares) |square, i| {
        if (square.piece()) |piece| {
            if (query_expr.exclude_king and piece.class() == .king)
                continue;
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
            const piece = board_dupe.squares[buffer[i]].piece().?;
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
            if (!board_dupe.hasVisability(buffer[i], coord.to1d(), query_expr.attacking orelse false)) {
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
    var iter = DirectionalIterator.init(source, dest);
    while (iter.next()) |coord| {
        if (board.at(coord)) |_|
            return false;
    }
    return true;
}

/// determines if affiliated king is in check and cannot
/// get out of check within a single move
fn isMate(board: *Board, affiliation: Affiliation) bool {
    const state = board.getMetaState(affiliation);
    if (!state.in_check)
        return false;

    var buffer: [32]usize = undefined;

    // can the king move to safety
    const file_start = std.math.clamp(state.king_coord.file - 1, 0, 7);
    const rank_start = std.math.clamp(state.king_coord.rank - 1, 0, 7);
    const file_end = std.math.clamp(state.king_coord.file + 1, 0, 7);
    const rank_end = std.math.clamp(state.king_coord.rank + 1, 0, 7);
    var coord = Coordinate.init(file_start, rank_start);
    while (coord.file <= file_end) {
        while (coord.rank <= rank_end) {
            // empty or enemy piece
            if (board.at(coord) == null or board.at(coord).?.affiliation() == affiliation.opponent()) {
                const attackers = board.query(&buffer, .{
                    .affiliation = affiliation.opponent(),
                    .attacking = true,
                    .target_coord = coord,
                    .hypothetical_move = .{
                        .piece = Piece.init(.king, affiliation),
                        .location = state.king_coord,
                        .destination = coord,
                    },
                });
                if (attackers.len == 0)
                    return false;
            }
            coord.rank += 1;
        }
        coord.rank = rank_start;
        coord.file += 1;
    }

    var checkers_buffer: [32]usize = undefined;
    const checkers = board.query(&checkers_buffer, .{
        .affiliation = affiliation.opponent(),
        .attacking = true,
        .target_coord = state.king_coord,
    });

    // double checks can't be blocked or captured
    if (checkers.len > 1)
        return true;

    // can we capture the checking piece
    const capturing = board.query(&buffer, .{
        .affiliation = affiliation,
        .attacking = true,
        .target_coord = Coordinate.from1d(checkers[0]),
    });
    if (capturing.len > 0)
        return false;

    // can we block the check
    switch (board.at(Coordinate.from1d(checkers[0])).?.class()) {
        .pawn,
        .knight,
        .king,
        => return true,
        else => {},
    }
    var iter = DirectionalIterator.init(state.king_coord, Coordinate.from1d(checkers[0]));
    while (iter.next()) |c| {
        const blockers = board.query(&buffer, .{
            .affiliation = affiliation,
            .target_coord = c,
            .exclude_king = true, // cannot block check with king
        });
        if (blockers.len > 0)
            return false;
    }

    return true;
}

/// looks for checks, mates, and draws
fn checksAndMates(board: *Board, affiliation: Affiliation) MoveResult {
    var state = board.getMetaState(affiliation);
    var buffer: [32]usize = undefined;
    const checkers = board.query(&buffer, .{
        .affiliation = affiliation.opponent(),
        .target_coord = state.king_coord,
        .attacking = true,
    });
    if (checkers.len > 0) {
        state.in_check = true;
        return if (board.isMate(affiliation))
            .ok_mate
        else
            .ok_check;
    }
    return .ok;
}

/// iterates over squares between two coords exclusive
const DirectionalIterator = struct {
    source: Coordinate,
    dest: Coordinate,
    at: Coordinate,
    delta: Coordinate,

    pub fn init(source: Coordinate, dest: Coordinate) DirectionalIterator {
        const rank_diff = dest.rank - source.rank;
        const file_diff = dest.file - source.file;
        const length = std.math.sqrt(@intCast(u8, rank_diff * rank_diff + file_diff * file_diff));
        const rank_delta = std.math.clamp(div(rank_diff, length), -1, 1);
        const file_delta = std.math.clamp(div(file_diff, length), -1, 1);
        return .{
            .source = source,
            .dest = dest,
            .at = source,
            .delta = .{ .rank = rank_delta, .file = file_delta },
        };
    }

    pub fn next(iter: *DirectionalIterator) ?Coordinate {
        iter.at = iter.at.offsetted(iter.delta.file, iter.delta.rank);
        if (!iter.at.valid()) return null;
        if (iter.at.to1d() == iter.dest.to1d()) return null;
        return iter.at;
    }
};

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
