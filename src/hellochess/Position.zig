// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

const std = @import("std");

const fen = @import("fen.zig");
const movegen = @import("movegen.zig");

const Piece = @import("Piece.zig");
const Notation = @import("Notation.zig");
const Coordinate = @import("Coordinate.zig");
const Move = @import("Move.zig");
const Meta = @import("Meta.zig");
const Bitboard = @import("Bitboard.zig");

const MoveIterator = movegen.MoveIterator;
const Class = Piece.Class;
const Affiliation = Piece.Affiliation;
const File = Coordinate.File;
const Rank = Coordinate.Rank;
const DirectionalIterator = Coordinate.DirectionalIterator;

const Position = @This();

/// the 64 squares of a chess board laid out a rank 1 to 8 file a to h
/// see Coordinate.to1d and Coordinate.from_1d for mapping
squares: [64]Piece,
/// stores castling rights, en passant target,
/// move counter, and last captured piece
meta: Meta,
/// cached king coords
kings: [2]Coordinate,
/// cached piece coords per affiliation
pieces: [2]Bitboard,
/// cached pawn coords per affiliation
pawns: [2]Bitboard,
/// cached knight coords per affiliation
knights: [2]Bitboard,
/// cached bishop coords per affiliation
bishops: [2]Bitboard,
/// cached rook coords per affiliation
rooks: [2]Bitboard,
/// cached queen coords per affiliation
queens: [2]Bitboard,
/// affiliation to make next move
side_to_move: Affiliation,
/// number of half moves played so far
ply: i32,

/// create an empty position, with only kings
pub fn initEmpty() Position {
    return empty_position;
}

/// create a position with standard chess starting position
pub fn init() Position {
    return starting_position;
}

/// create a position from a fen string
/// see fen.zig
pub fn fromFen(fen_str: []const u8) fen.Error!Position {
    return try fen.parse(fen_str);
}

/// return a duplicate of `position`
pub fn dupe(position: Position) Position {
    return position;
}

/// return piece at coord
pub fn at(position: Position, pos: Coordinate) Piece {
    return position.squares[pos.index()];
}

/// returns a bitboard marking all coords in `position` with
/// pieces matching `affiliation` and `class`
pub fn bitboard(position: Position, affiliation: Affiliation, class: ?Class) Bitboard {
    const i = affiliation.index();
    return switch (class orelse return position.pieces[i]) {
        .queen => position.queens[i],
        .rook => position.rooks[i],
        .bishop => position.bishops[i],
        .knight => position.knights[i],
        .pawn => position.pawns[i],
        .king => blk: {
            var board = Bitboard.init();
            board.set(position.kings[0], true);
            board.set(position.kings[1], true);
            break :blk board;
        },
    };
}

/// returns coord of current side to move's king
pub fn kingCoord(position: Position) Coordinate {
    return position.kings[position.side_to_move.index()];
}

/// counts material value for given affiliation
pub fn countMaterial(position: Position, affiliation: Affiliation) i32 {
    var buffer: [32]Coordinate = undefined;
    const pieces = position.query(&buffer, .{
        .affiliation = affiliation,
        .exclude_king = true,
    });
    var material: i32 = 0;
    for (pieces) |coord| {
        material += position.at(coord).class().?.value();
    }
    return material;
}

/// write pieces missing from affiliated posistion
pub fn writeCapturedPieces(position: Position, writer: anytype, affiliation: Affiliation) !void {
    var buffer: [32]Coordinate = undefined;
    const pieces = position.query(&buffer, .{
        .affiliation = affiliation,
        .exclude_king = true,
    });
    var pawns: i32 = 0;
    var bishops: i32 = 0;
    var knights: i32 = 0;
    var rooks: i32 = 0;
    var queens: i32 = 0;
    for (pieces) |coord| {
        switch (position.at(coord).class().?) {
            .pawn => pawns += 1,
            .bishop => bishops += 1,
            .knight => knights += 1,
            .rook => rooks += 1,
            .queen => queens += 1,
            .king => {},
        }
    }
    try writer.writeByteNTimes('P', @intCast(usize, std.math.max(8 - pawns, 0)));
    try writer.writeByteNTimes('B', @intCast(usize, std.math.max(2 - bishops, 0)));
    try writer.writeByteNTimes('N', @intCast(usize, std.math.max(2 - knights, 0)));
    try writer.writeByteNTimes('R', @intCast(usize, std.math.max(2 - rooks, 0)));
    try writer.writeByteNTimes('Q', @intCast(usize, std.math.max(1 - queens, 0)));
}

/// spawn piece at given coord for side to move
pub fn spawn(position: *Position, class: Class, coord: Coordinate) Move.Result {
    const piece = Piece.init(class, position.side_to_move);
    position.squares[coord.index()] = piece;
    position.pieces[position.side_to_move.index()].set(coord, true);
    if (class == .king) {
        position.squares[position.kingCoord().index()] = Piece.empty();
        position.kings[position.side_to_move.index()] = coord;
        if (coord.eql(position.side_to_move.kingCoord())) {
            if (position.squares[position.side_to_move.aRookCoord().index()].is(.rook, position.side_to_move))
                position.meta.setCastleQueen(position.side_to_move, true);
            if (position.squares[position.side_to_move.hRookCoord().index()].is(.rook, position.side_to_move))
                position.meta.setCastleKing(position.side_to_move, true);
        }
    } else if (class == .rook and position.kingCoord().eql(position.side_to_move.kingCoord())) {
        if (coord.eql(position.side_to_move.aRookCoord()))
            position.meta.setCastleQueen(position.side_to_move, true);
        if (coord.eql(position.side_to_move.hRookCoord()))
            position.meta.setCastleKing(position.side_to_move, true);
    }
    position.side_to_move = position.side_to_move.opponent();

    // update class bitboard
    switch (class) {
        .queen => position.queens[position.side_to_move.index()].set(coord, true),
        .rook => position.rooks[position.side_to_move.index()].set(coord, true),
        .bishop => position.bishops[position.side_to_move.index()].set(coord, true),
        .knight => position.knights[position.side_to_move.index()].set(coord, true),
        .pawn => position.pawns[position.side_to_move.index()].set(coord, true),
        .king => {},
    }

    return position.checksAndMates();
}

/// makes a move, no validation, no searching for checks or mates
pub fn doMove(position: *Position, move: Move) void {
    var piece = position.at(move.source());
    var captured = position.at(move.dest());
    if (piece.isEmpty()) return;

    position.meta.setEnpassantFile(null);

    if (piece.class().? == .king) {
        position.kings[position.side_to_move.index()] = move.dest();
        position.meta.setCastleKing(position.side_to_move, false);
        position.meta.setCastleQueen(position.side_to_move, false);
    }

    if (move.promotion()) |promotion_class| {
        piece = Piece.init(promotion_class, position.side_to_move);
    } else switch (move.flag()) {
        .none => {},
        .enpassant_capture => {
            const coord = move.dest().offsettedDir(position.side_to_move.reverseDirection(), 1).?;
            captured = position.at(coord);
            position.squares[coord.index()] = Piece.empty();
        },
        .castle => {
            const kingside = move.dest().eql(Coordinate.g1) or move.dest().eql(Coordinate.g8);
            const rook_source = if (kingside)
                move.dest().offsettedDir(.east, 1).?
            else
                move.dest().offsettedDir(.west, 2).?;
            const rook_dest = if (kingside)
                move.dest().offsettedDir(.west, 1).?
            else
                move.dest().offsettedDir(.east, 1).?;
            position.squares[rook_source.index()] = Piece.empty();
            position.squares[rook_dest.index()] = Piece.init(.rook, position.side_to_move);
        },
        .pawn_double_push => {
            const file = move.source().getFile();
            position.meta.setEnpassantFile(file);
        },
        else => unreachable,
    }

    // update class bitboards
    switch (piece.class().?) {
        .queen => {
            position.queens[position.side_to_move.index()].set(move.source(), false);
            position.queens[position.side_to_move.index()].set(move.dest(), true);
        },
        .rook => {
            position.rooks[position.side_to_move.index()].set(move.source(), false);
            position.rooks[position.side_to_move.index()].set(move.dest(), true);
        },
        .bishop => {
            position.bishops[position.side_to_move.index()].set(move.source(), false);
            position.bishops[position.side_to_move.index()].set(move.dest(), true);
        },
        .knight => {
            position.knights[position.side_to_move.index()].set(move.source(), false);
            position.knights[position.side_to_move.index()].set(move.dest(), true);
        },
        .pawn => {
            position.pawns[position.side_to_move.index()].set(move.source(), false);
            position.pawns[position.side_to_move.index()].set(move.dest(), true);
        },
        .king => {},
    }

    position.pieces[position.side_to_move.index()].set(move.source(), false);
    position.pieces[position.side_to_move.index()].set(move.dest(), true);
    position.squares[move.source().index()] = Piece.empty();
    position.squares[move.dest().index()] = piece;
    position.ply += 1;
    position.side_to_move = position.side_to_move.opponent();

    position.meta.setCapturedPiece(captured);
    position.meta.incFiftyCounter();
    if (!captured.isEmpty() or piece.class().? == .pawn or move.promotion() != null)
        position.meta.setFiftyCounter(0);

    // update castling rights
    if (move.dest().eql(Coordinate.h1) or move.source().eql(Coordinate.h1))
        position.meta.setCastleKing(.white, false);
    if (move.dest().eql(Coordinate.a1) or move.source().eql(Coordinate.a1))
        position.meta.setCastleQueen(.white, false);
    if (move.dest().eql(Coordinate.h8) or move.source().eql(Coordinate.h8))
        position.meta.setCastleKing(.black, false);
    if (move.dest().eql(Coordinate.a8) or move.source().eql(Coordinate.a8))
        position.meta.setCastleQueen(.black, false);
}

/// submit move, move to be made pending validation
/// uses standard chess notation (https://en.wikipedia.org/wiki/Algebraic_notation_(chess))
pub fn submitMove(position: *Position, move_notation: []const u8) Move.Result {
    const notation = Notation.parse(move_notation) orelse return .bad_notation;

    // cannot capture allied pieces
    if (position.at(notation.destination).affiliation()) |affiliation| {
        if (affiliation == position.side_to_move)
            return .blocked;
    }

    var buffer: [32]Move = undefined;
    const moves = position.findMoves(
        &buffer,
        position.bitboard(position.side_to_move, notation.class),
        notation.destination,
        notation.source_file,
        notation.source_rank,
    ) catch unreachable;

    if (moves.len > 1)
        return .ambiguous_piece;
    if (moves.len == 0)
        return .no_visibility;

    const move = moves[0];

    position.doMove(move);
    return position.checksAndMates();
}

/// returns moves that the marked pieces in `coords` can make
/// that land on `target` coord. if `coords` marks an empty square
/// it is ignored. moves are written into `buffer`, if buffer cannot
/// fit all moves error.BufferOverflow is returned
/// `rank` specifies expected starting rank
/// `file` specifies expected starting file
pub fn findMoves(position: Position, buffer: []Move, coords: Bitboard, target: Coordinate, file: ?File, rank: ?Rank) ![]Move {
    var i: usize = 0;
    var coord_iter = coords.iterator();
    coord_loop: while (coord_iter.next()) |coord| {
        if (position.at(coord).isEmpty())
            continue :coord_loop;
        if (file != null and coord.getFile() != file.?)
            continue :coord_loop;
        if (rank != null and coord.getRank() != rank.?)
            continue :coord_loop;
        var move_iter = try MoveIterator.init(&position, coord);
        move_loop: while (move_iter.next()) |move| {
            if (move.dest().eql(target)) {
                // MoveIterator returns psuedo legal moves
                // ensure move is legal
                var p = position;
                p.doMove(move);
                if (p.inCheck(position.at(coord).affiliation().?))
                    continue :move_loop;
                buffer[i] = move;
                i += 1;
            }
        }
    }
    return buffer[0..i];
}

pub fn inCheck(position: Position, affiliation: Affiliation) bool {
    const target = position.kings[affiliation.index()];
    const opponents = position.bitboard(affiliation.opponent(), null);
    var coord_iter = opponents.iterator();
    while (coord_iter.next()) |coord| {
        var move_iter = MoveIterator.init(&position, coord) catch continue;
        while (move_iter.next()) |move| {
            if (move.dest().eql(target))
                return true;
        }
    }
    return false;
}

/// returns if current side to move has casling rights
/// for given direction
pub fn canCastle(position: Position, kingside: bool) bool {
    return if (kingside)
        position.meta.castleKing(position.side_to_move)
    else
        position.meta.castleQueen(position.side_to_move);
}

/// attempt to castle, pending validation
pub fn castle(position: *Position, kingside: bool) Move.Result {
    if (!position.canCastle(kingside))
        return .bad_castle_king_or_rook_moved;

    // cannot castle out of check
    var buffer: [32]Coordinate = undefined;
    const checker = position.query(&buffer, .{
        .affiliation = position.side_to_move.opponent(),
        .attacking = true,
        .target_coord = position.kingCoord(),
    });
    if (checker.len > 0)
        return .bad_castle_in_check;

    // cannot castle through check
    const file_delta: i8 = if (kingside) 3 else -4;
    var iter = DirectionalIterator.initWithDest(position.kingCoord(), position.kingCoord().offsetted(file_delta, 0).?) catch unreachable;
    while (iter.next()) |coord| {
        if (!position.at(coord).isEmpty())
            return .blocked;
        const attackers = position.query(&buffer, .{
            .affiliation = position.side_to_move.opponent(),
            .attacking = true,
            .target_coord = coord,
        });
        if (attackers.len > 0)
            return .bad_castle_through_check;
    }

    return position.makeMove(Move.init(
        position.kingCoord(),
        position.kingCoord().offsettedDir(if (kingside) .east else .west, 2).?,
        .castle,
    ));
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
    source_file: ?File = null,
    /// search for pieces on this rank
    source_rank: ?Rank = null,
    /// query position as if this move was made
    hypothetical_move: ?Move = null,
    /// exclude kings from results
    exclude_king: bool = false,
};

/// query's the position for pieces meeting constraints defined in `query_expr`
/// **buffer:** buffer to write results to
/// **query_expr:** constraints to search for
/// **returns:** slice into `buffer` containing 1d coordinates of matching pieces
pub fn query(position: Position, buffer: *[32]Coordinate, query_expr: Query) []const Coordinate {
    var count: usize = 0;

    var duped = position.dupe();
    if (query_expr.hypothetical_move) |move|
        duped.doMove(move);

    // write initial pieces with expected affiliation
    for (duped.squares, 0..) |piece, i| {
        if (!piece.isEmpty()) {
            if (query_expr.exclude_king and piece.class().? == .king)
                continue;
            if (query_expr.affiliation) |affiliation| {
                if (piece.affiliation().? == affiliation) {
                    buffer[count] = Coordinate.from1d(@intCast(i8, i));
                    count += 1;
                }
            } else {
                buffer[count] = Coordinate.from1d(@intCast(i8, i));
                count += 1;
            }
        }
    }

    // filter with expected class
    if (query_expr.class) |class| {
        var i: usize = 0;
        while (i < count) {
            const piece = duped.at(buffer[i]);
            if (piece.class().? != class) {
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
            if (!duped.hasVisability(buffer[i], coord, query_expr.attacking orelse false)) {
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
            if (buffer[i].getFile() != file) {
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
            if (buffer[i].getRank() != rank) {
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
/// attacking ensures that the source piece can capture on dest, important for pawns
/// takes source and dest as 1d coordinates
fn hasVisability(position: *Position, source: Coordinate, dest: Coordinate, attacking: bool) bool {
    // pawns only attack diagonaly
    if (attacking and position.at(source).class().? == .pawn and source.getFile() == dest.getFile())
        return false;
    var move_iter = MoveIterator.init(position, source) catch unreachable;
    while (move_iter.next()) |move| {
        if (move.dest().eql(dest)) {
            return true;
        }
    }
    return false;
}

/// ensures all squares between source and dest are empty
fn ensureEmpty(position: Position, source: Coordinate, dest: Coordinate) bool {
    var iter = DirectionalIterator.initWithDest(source, dest) catch unreachable;
    while (iter.next()) |coord| {
        if (!position.at(coord).isEmpty())
            return false;
    }
    return true;
}

/// determines if affiliated king is in check and cannot
/// get out of check within a single move
fn isMate(position: *Position) bool {
    var checkers_buffer: [32]Coordinate = undefined;
    const checkers = position.query(&checkers_buffer, .{
        .affiliation = position.side_to_move.opponent(),
        .attacking = true,
        .target_coord = position.kingCoord(),
    });

    // not even in check
    if (checkers.len == 0) return false;

    // can the king move to safety
    var buffer: [32]Coordinate = undefined;
    const file_start = std.math.clamp(position.kingCoord().getFile().val() - 1, 0, 7);
    const rank_start = std.math.clamp(position.kingCoord().getRank().val() - 1, 0, 7);
    const file_end = std.math.clamp(position.kingCoord().getFile().val() + 1, 0, 7);
    const rank_end = std.math.clamp(position.kingCoord().getRank().val() + 1, 0, 7);
    var file_iter = File.init(file_start).iterator();
    while (file_iter.next()) |file| {
        if (file.val() > file_end) break;
        var rank_iter = Rank.init(rank_start).iterator();
        while (rank_iter.next()) |rank| {
            if (rank.val() > rank_end) break;
            const coord = Coordinate.from2d(file, rank);
            // empty or enemy piece
            if (position.at(coord).isEmpty() or
                position.at(coord).affiliation().? == position.side_to_move.opponent())
            {
                const attackers = position.query(&buffer, .{
                    .affiliation = position.side_to_move.opponent(),
                    .attacking = true,
                    .target_coord = coord,
                    .hypothetical_move = Move.init(position.kingCoord(), coord, .none),
                });
                if (attackers.len == 0)
                    return false;
            }
        }
    }

    // double checks can't be blocked or captured
    if (checkers.len > 1)
        return true;

    // can we capture the checking piece
    const capturing = position.query(&buffer, .{
        .affiliation = position.side_to_move,
        .attacking = true,
        .target_coord = checkers[0],
        .exclude_king = true, // king capture handled above
    });
    if (capturing.len > 0)
        return false;

    // can we block the check
    switch (position.at(checkers[0]).class().?) {
        // theese pieces cannot be blocked
        .pawn, .knight, .king => return true,
        else => {},
    }
    var iter = DirectionalIterator.initWithDest(position.kingCoord(), checkers[0]) catch unreachable;
    while (iter.next()) |c| {
        const blockers = position.query(&buffer, .{
            .affiliation = position.side_to_move,
            .target_coord = c,
            .exclude_king = true, // cannot block check with king
        });
        if (blockers.len > 0)
            return false;
    }

    return true;
}

/// looks for checks, mates, and draws
fn checksAndMates(position: *Position) Move.Result {
    if (position.inCheck(position.side_to_move)) {
        return if (position.isMate())
            .ok_mate
        else
            .ok_check;
    }
    return .ok;
}

/// divide n / d rounding away from zero
fn div(n: i8, d: i8) i8 {
    const quotiant = @intToFloat(f32, n) / @intToFloat(f32, d);
    const sign = std.math.sign(quotiant);
    const val = @fabs(quotiant);
    return @floatToInt(i8, @ceil(val) * sign);
}

/// helper for absolute values
/// std.math.absInt() errors when val is minInt()
/// as -minInt() is overflow by 1
/// we just return maxInt() in this case
/// off by one but it's fine don't worry about it
fn abs(val: i8) i8 {
    return std.math.absInt(val) catch std.math.maxInt(i8);
}

/// standard chess starting position
const starting_position = fen.parse(fen.starting_position) catch unreachable;
/// position for empty boards, kings must always exist
const empty_position = fen.parse("4k3/8/8/8/8/8/8/4K3 w - - 0 1") catch unreachable;
