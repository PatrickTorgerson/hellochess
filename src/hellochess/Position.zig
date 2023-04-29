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
    const pieces = position.bitboard(affiliation, null);
    var material: i32 = 0;
    var iter = pieces.iterator();
    while (iter.next()) |coord| {
        material += position.at(coord).class().?.value();
    }
    return material;
}

/// write pieces missing from affiliated posistion
pub fn writeCapturedPieces(position: Position, writer: anytype, affiliation: Affiliation) !void {
    const i = affiliation.index();
    try writer.writeByteNTimes('P', 8 -| position.pawns[i].count());
    try writer.writeByteNTimes('B', 2 -| position.bishops[i].count());
    try writer.writeByteNTimes('N', 2 -| position.knights[i].count());
    try writer.writeByteNTimes('R', 2 -| position.rooks[i].count());
    try writer.writeByteNTimes('Q', 1 -| position.queens[i].count());
}

/// spawn piece at given coord for side to move
pub fn spawn(position: *Position, class: Class, coord: Coordinate) Move.Result.Tag {
    const piece = Piece.init(class, position.side_to_move);

    if (!position.squares[coord.index()].isEmpty())
        position.meta.setCapturedPiece(position.squares[coord.index()]);

    position.squares[coord.index()] = piece;
    position.pieces[position.side_to_move.index()].set(coord, true);
    position.pieces[position.side_to_move.opponent().index()].set(coord, false);

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

    // update class bitboard
    switch (class) {
        .queen => {
            position.queens[position.side_to_move.index()].set(coord, true);
            position.queens[position.side_to_move.opponent().index()].set(coord, false);
        },
        .rook => {
            position.rooks[position.side_to_move.index()].set(coord, true);
            position.rooks[position.side_to_move.opponent().index()].set(coord, false);
        },
        .bishop => {
            position.bishops[position.side_to_move.index()].set(coord, true);
            position.bishops[position.side_to_move.opponent().index()].set(coord, false);
        },
        .knight => {
            position.knights[position.side_to_move.index()].set(coord, true);
            position.knights[position.side_to_move.opponent().index()].set(coord, false);
        },
        .pawn => {
            position.pawns[position.side_to_move.index()].set(coord, true);
            position.pawns[position.side_to_move.opponent().index()].set(coord, false);
        },
        .king => {},
    }

    position.side_to_move = position.side_to_move.opponent();
    return position.checksAndMates();
}

/// makes a move, no validation, no searching for checks or mates
pub fn doMove(position: *Position, move: Move) void {
    var piece = position.at(move.source());
    var captured = position.at(move.dest());
    if (piece.isEmpty()) return;

    position.meta.setEnpassantFile(null);

    if (move.promotion()) |promotion_class| {
        piece = Piece.init(promotion_class, position.side_to_move);
        position.pawns[position.side_to_move.index()].set(move.source(), false);
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
            position.pieces[position.side_to_move.index()].set(rook_source, false);
            position.pieces[position.side_to_move.index()].set(rook_dest, true);
            position.rooks[position.side_to_move.index()].set(rook_source, false);
            position.rooks[position.side_to_move.index()].set(rook_dest, true);
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
        .king => {
            position.kings[position.side_to_move.index()] = move.dest();
            position.meta.setCastleKing(position.side_to_move, false);
            position.meta.setCastleQueen(position.side_to_move, false);
        },
    }

    if (!captured.isEmpty()) {
        const i = position.side_to_move.opponent().index();
        position.pieces[i].set(move.dest(), false);
        switch (captured.class().?) {
            .queen => position.queens[i].set(move.dest(), false),
            .rook => position.rooks[i].set(move.dest(), false),
            .bishop => position.bishops[i].set(move.dest(), false),
            .knight => position.knights[i].set(move.dest(), false),
            .pawn => position.pawns[i].set(move.dest(), false),
            .king => {},
        }
    }

    position.pieces[position.side_to_move.index()].set(move.source(), false);
    position.pieces[position.side_to_move.index()].set(move.dest(), true);
    position.squares[move.source().index()] = Piece.empty();
    position.squares[move.dest().index()] = piece;
    position.ply += 1;

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

    position.side_to_move = position.side_to_move.opponent();
}

pub fn undoMove(position: *Position, move: Move, prev_meta: Meta) void {
    position.side_to_move = position.side_to_move.opponent();

    const piece = if (move.promotion()) |class| blk: {
        switch (class) {
            .queen => position.queens[position.side_to_move.index()].set(move.dest(), false),
            .rook => position.rooks[position.side_to_move.index()].set(move.dest(), false),
            .bishop => position.bishops[position.side_to_move.index()].set(move.dest(), false),
            .knight => position.knights[position.side_to_move.index()].set(move.dest(), false),
            else => unreachable,
        }
        break :blk Piece.init(.pawn, position.side_to_move);
    } else position.at(move.dest());

    // update class bitboards
    switch (piece.class().?) {
        .queen => {
            position.queens[position.side_to_move.index()].set(move.source(), true);
            position.queens[position.side_to_move.index()].set(move.dest(), false);
        },
        .rook => {
            position.rooks[position.side_to_move.index()].set(move.source(), true);
            position.rooks[position.side_to_move.index()].set(move.dest(), false);
        },
        .bishop => {
            position.bishops[position.side_to_move.index()].set(move.source(), true);
            position.bishops[position.side_to_move.index()].set(move.dest(), false);
        },
        .knight => {
            position.knights[position.side_to_move.index()].set(move.source(), true);
            position.knights[position.side_to_move.index()].set(move.dest(), false);
        },
        .pawn => {
            position.pawns[position.side_to_move.index()].set(move.source(), true);
            position.pawns[position.side_to_move.index()].set(move.dest(), false);
        },
        .king => {
            position.kings[position.side_to_move.index()] = move.source();
        },
    }

    if (!position.meta.capturedPiece().isEmpty()) {
        const i = position.side_to_move.opponent().index();
        position.pieces[i].set(move.dest(), true);
        switch (position.meta.capturedPiece().class().?) {
            .queen => position.queens[i].set(move.dest(), true),
            .rook => position.rooks[i].set(move.dest(), true),
            .bishop => position.bishops[i].set(move.dest(), true),
            .knight => position.knights[i].set(move.dest(), true),
            .pawn => position.pawns[i].set(move.dest(), true),
            .king => {},
        }
    }

    position.pieces[position.side_to_move.index()].set(move.source(), true);
    position.pieces[position.side_to_move.index()].set(move.dest(), false);
    position.squares[move.source().index()] = piece;

    switch (move.flag()) {
        .enpassant_capture => {
            const coord = move.dest().offsettedDir(position.side_to_move.reverseDirection(), 1).?;
            position.squares[coord.index()] = position.meta.capturedPiece();
            position.squares[move.dest().index()] = Piece.empty();
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
            position.squares[rook_source.index()] = Piece.init(.rook, position.side_to_move);
            position.squares[rook_dest.index()] = Piece.empty();
            position.squares[move.dest().index()] = position.meta.capturedPiece();
            position.pieces[position.side_to_move.index()].set(rook_source, true);
            position.pieces[position.side_to_move.index()].set(rook_dest, false);
            position.rooks[position.side_to_move.index()].set(rook_source, true);
            position.rooks[position.side_to_move.index()].set(rook_dest, false);
        },
        else => position.squares[move.dest().index()] = position.meta.capturedPiece(),
    }

    position.ply -= 1;
    position.meta = prev_meta;
}

/// submit move, move to be made pending validation
/// uses standard chess notation (https://en.wikipedia.org/wiki/Algebraic_notation_(chess))
pub fn submitMove(position: *Position, move_notation: []const u8) Move.Result {
    const prev_meta = position.meta;
    var notation = Notation.parse(move_notation) orelse return .{
        .tag = .bad_notation,
        .prev_meta = prev_meta,
    };

    if (notation.castle_kingside) |kingside| {
        notation.class = .king;
        notation.source_file = .file_e;
        if (kingside)
            notation.destination = position.side_to_move.kingCastleDest()
        else
            notation.destination = position.side_to_move.queenCastleDest();
    }

    // cannot capture allied pieces
    if (position.at(notation.destination).affiliation()) |affiliation| {
        if (affiliation == position.side_to_move)
            return .{
                .tag = .blocked,
                .prev_meta = prev_meta,
            };
    }

    const promotion_rank = position.side_to_move.opponent().backRank();
    const required_flag = if (notation.class == .pawn and notation.destination.getRank() == promotion_rank)
        notation.promote_to orelse .promote_queen
    else
        null;

    var buffer: [32]Move = undefined;
    const moves = position.findMoves(
        &buffer,
        position.bitboard(position.side_to_move, notation.class),
        notation.destination,
        .{ // filters
            .file = notation.source_file,
            .rank = notation.source_rank,
            .flag = required_flag,
        },
    ) catch unreachable;

    if (moves.len == 0)
        return .{
            .tag = .no_visibility,
            .prev_meta = prev_meta,
        };
    if (moves.len > 1)
        return .{
            .tag = .ambiguous_piece,
            .prev_meta = prev_meta,
        };

    const move = moves[0];

    position.doMove(move);
    return .{
        .move = move,
        .tag = position.checksAndMates(),
        .prev_meta = prev_meta,
    };
}

pub const MoveFilters = struct {
    file: ?File = null,
    rank: ?Rank = null,
    flag: ?Move.Flag = null,
};

/// returns moves that the marked pieces in `coords` can make
/// that land on `target` coord. if `coords` marks an empty square
/// it is ignored. moves are written into `buffer`, if buffer cannot
/// fit all moves error.BufferOverflow is returned
/// `rank` specifies expected starting rank
/// `file` specifies expected starting file
pub fn findMoves(position: Position, buffer: []Move, coords: Bitboard, target: Coordinate, filters: MoveFilters) ![]Move {
    var i: usize = 0;
    var coord_iter = coords.iterator();
    coord_loop: while (coord_iter.next()) |coord| {
        if (position.at(coord).isEmpty())
            continue :coord_loop;
        if (filters.file != null and coord.getFile() != filters.file.?)
            continue :coord_loop;
        if (filters.rank != null and coord.getRank() != filters.rank.?)
            continue :coord_loop;
        var move_iter = try MoveIterator.init(&position, coord);
        move_loop: while (move_iter.next()) |move| {
            if (filters.flag != null and move.flag() != filters.flag)
                continue :move_loop;
            if (move.dest().eql(target)) {
                // MoveIterator returns psuedo legal moves
                // ensure move is legal
                var p = position;
                p.doMove(move);
                if (p.inCheck(position.at(coord).affiliation().?))
                    continue :move_loop;
                if (i >= buffer.len)
                    return error.BufferOverflow;
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

/// looks for checks, mates, and draws
pub fn checksAndMates(position: Position) Move.Result.Tag {
    const in_check = position.inCheck(position.side_to_move);
    const available_moves = position.hasLegalMoves(position.side_to_move);

    if (in_check and !available_moves) return .ok_mate;
    if (position.meta.fiftyCounter() >= 100) return .ok_fifty_move_rule;
    if (in_check and available_moves) return .ok_check;
    if (!in_check and !available_moves) return .ok_stalemate;

    // TODO: insufficiant material
    // TODO: repitition

    return .ok;
}

/// determines if any affiliated pieces have legal moves available
pub fn hasLegalMoves(position: Position, affiliation: Affiliation) bool {
    var buffer: [128]Move = undefined;
    const moves = movegen.generateMoves(&buffer, position, affiliation) catch return true;
    for (moves) |move| {
        // filter illegals
        var p = position;
        p.doMove(move);
        if (p.inCheck(affiliation))
            continue // a move that puts or leaves us in check is illegal
        else
            return true;
    }
    return false;
}

/// standard chess starting position
const starting_position = fen.parse(fen.starting_position) catch unreachable;
/// position for empty boards, kings must always exist
const empty_position = fen.parse("4k3/8/8/8/8/8/8/4K3 w - - 0 1") catch unreachable;
