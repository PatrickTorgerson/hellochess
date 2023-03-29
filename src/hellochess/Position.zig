// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

const std = @import("std");

const Piece = @import("Piece.zig");
const Notation = @import("Notation.zig");
const Coordinate = @import("Coordinate.zig");
const Move = @import("Move.zig");
const Meta = @import("Meta.zig");

const Class = Piece.Class;
const Affiliation = Piece.Affiliation;
const File = Coordinate.File;
const Rank = Coordinate.Rank;

const Position = @This();

/// the 64 squares of a chess board laid out a rank 1 to 8 file a to h
/// see Coordinate.to1d and Coordinate.from_1d for mapping
squares: [64]Piece,
meta: Meta,
white_king: Coordinate = Coordinate.e1,
black_king: Coordinate = Coordinate.e8,
side_to_move: Affiliation,
/// number of half moves played so far
ply: i32 = 0,
/// number of half moves since last capture or pawn move
fifty_move_counter: i32 = 0,

/// create an empty position, with only kings
pub fn initEmpty() Position {
    var this = Position{
        .squares = [1]Piece{Piece.empty()} ** 64,
        .meta = Meta.initEmpty(),
        .side_to_move = .white,
    };
    this.squares[Affiliation.white.kingCoord().index()] = Piece.init(.king, .white);
    this.squares[Affiliation.black.kingCoord().index()] = Piece.init(.king, .black);
    return this;
}

/// create a position with standard chess starting position
pub fn init() Position {
    return .{
        .squares = starting_position,
        .meta = Meta.init(.{}),
        .side_to_move = .white,
    };
}

/// return a duplicate of position
pub fn dupe(position: Position) Position {
    return position;
}

/// return piece at coord
pub fn at(position: Position, pos: Coordinate) Piece {
    return position.squares[pos.index()];
}

/// returns coord of current side to move's king
pub fn kingCoord(position: Position) Coordinate {
    return switch (position.side_to_move) {
        .white => position.white_king,
        .black => position.black_king,
    };
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
    if (class == .king) {
        position.squares[position.kingCoord().index()] = Piece.empty();
        switch (position.side_to_move) {
            .white => position.white_king = coord,
            .black => position.black_king = coord,
        }
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
    return position.checksAndMates();
}

/// makes a move, no validation, no searching for checks or mates
/// returns null when move result is ok but potentially a check or mate
pub fn doMove(position: *Position, move: Move) void {
    var piece = position.at(move.source());
    var captured = position.at(move.dest());
    if (piece.isEmpty()) return;

    position.meta.setEnpassantFile(null);

    if (piece.class().? == .king) {
        switch (position.side_to_move) {
            .white => position.white_king = move.dest(),
            .black => position.black_king = move.dest(),
        }
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

    position.squares[move.source().index()] = Piece.empty();
    position.squares[move.dest().index()] = piece;
    position.ply += 1;
    position.fifty_move_counter += 1;
    position.side_to_move = position.side_to_move.opponent();

    if (!captured.isEmpty() or piece.class().? == .pawn or move.promotion() != null)
        position.fifty_move_counter = 0;

    position.meta.setCapturedPiece(captured);
    position.meta.setFiftyCounter(position.fifty_move_counter);

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

/// moves a pices to a different square, does no validation
pub fn makeMove(position: *Position, move: Move) Move.Result {
    position.doMove(move);
    return position.checksAndMates();
}

/// submit move, move to be made pending validation
/// uses standard chess notation (https://en.wikipedia.org/wiki/Algebraic_notation_(chess))
pub fn submitMove(position: *Position, move_notation: []const u8) Move.Result {
    const notation = Notation.parse(move_notation) orelse return .bad_notation;

    if (notation.castle_kingside) |castle_kingside| {
        return position.castle(castle_kingside);
    }

    // cannot capture allied pieces
    if (position.at(notation.destination).affiliation()) |affiliation| {
        if (affiliation == position.side_to_move)
            return .blocked;
    }

    var buffer: [32]Coordinate = undefined;
    const results = position.query(&buffer, .{
        .class = notation.class,
        .affiliation = position.side_to_move,
        .target_coord = notation.destination,
        .source_file = notation.source_file,
        .source_rank = notation.source_rank,
    });

    if (results.len > 1)
        return .ambiguous_piece;
    if (results.len == 0)
        return .no_visibility;

    const source = results[0];

    var move_flag: Move.Flag = .none;

    if (position.at(source).class().? == .pawn and notation.destination.getRank() == position.side_to_move.opponent().backRank()) {
        const promote_to: Class = notation.promote_to orelse .queen;
        move_flag = switch (promote_to) {
            .knight => .promote_knight,
            .bishop => .promote_bishop,
            .rook => .promote_rook,
            .queen => .promote_queen,
            else => return .bad_notation,
        };
    } else if (position.at(source).class().? == .pawn and
        notation.destination.getRank() == position.side_to_move.doublePushRank() and
        source.getRank() == position.side_to_move.secondRank())
        move_flag = .pawn_double_push
    else if (position.at(source).class().? == .pawn and
        source.getRank() == position.side_to_move.enPassantRank() and
        source.getFile() != notation.destination.getFile() and
        position.meta.enpassantFile() == notation.destination.getFile())
        move_flag = .enpassant_capture;

    const move = Move.init(source, notation.destination, move_flag);

    if (position.at(source).class().? == .king) {
        const attackers = position.query(&buffer, .{
            .affiliation = position.side_to_move.opponent(),
            .target_coord = notation.destination,
            .attacking = true,
            .hypothetical_move = move,
        });
        if (attackers.len > 0)
            return .enters_check;
    } else {
        const checkers = position.query(&buffer, .{
            .affiliation = position.side_to_move.opponent(),
            .target_coord = position.kingCoord(),
            .hypothetical_move = move,
            .attacking = true,
        });
        if (checkers.len > 0)
            return .enters_check;
    }

    return position.makeMove(move);
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
    var iter = DirectionalIterator.init(position.kingCoord(), position.kingCoord().offsetted(file_delta, 0).?);
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
    if (dest.eql(source))
        return false;
    const piece = position.at(source);
    if (piece.isEmpty()) return false;
    const class = piece.class().?;
    const affiliation = piece.affiliation().?;
    const sfile = source.getFile().val();
    const srank = source.getRank().val();
    const dfile = dest.getFile().val();
    const drank = dest.getRank().val();
    switch (class) {
        .pawn => {
            if (attacking) {
                return (drank == srank + affiliation.direction().offset()) and
                    (dfile == sfile + 1 or dfile == sfile - 1);
            } else {
                // double push
                if (drank == affiliation.doublePushRank().val() and srank == affiliation.secondRank().val()) {
                    return dfile == sfile and
                        position.at(source.offsettedDir(affiliation.direction(), 1).?).isEmpty() and
                        position.at(dest).isEmpty();
                }
                // single push
                if (dfile == sfile and drank == srank + affiliation.direction().offset())
                    return position.at(dest).isEmpty();
                // captures
                if ((dfile == sfile + 1 or dfile == sfile - 1) and drank == srank + affiliation.direction().offset()) {
                    if (position.at(dest).isEmpty()) {
                        // en passant
                        const coord = dest.offsettedDir(affiliation.reverseDirection(), 1).?;
                        const enpassant_target = position.at(coord);
                        if (!enpassant_target.isEmpty()) {
                            const enpassant_file = position.meta.enpassantFile();
                            return (enpassant_target.class().? == .pawn and
                                enpassant_target.affiliation().? == affiliation.opponent() and
                                enpassant_file != null and
                                enpassant_file.?.val() == dfile);
                        }
                    } else return position.at(dest).affiliation().? == affiliation.opponent();
                }
                return false;
            }
        },
        .knight => {
            const rank_diff: i8 = abs(drank - srank);
            const file_diff: i8 = abs(dfile - sfile);
            return (rank_diff == 2 and file_diff == 1) or (rank_diff == 1 and file_diff == 2);
        },
        .bishop => {
            const rank_diff: i8 = abs(drank - srank);
            const file_diff: i8 = abs(dfile - sfile);
            if (rank_diff != file_diff)
                return false;
            return position.ensureEmpty(source, dest);
        },
        .rook => {
            if (drank != srank and dfile != sfile)
                return false;
            return position.ensureEmpty(source, dest);
        },
        .queen => {
            const rank_diff: i8 = abs(drank - srank);
            const file_diff: i8 = abs(dfile - sfile);
            if (drank != srank and dfile != sfile and
                rank_diff != file_diff)
                return false;
            return position.ensureEmpty(source, dest);
        },
        .king => {
            if (dfile > sfile + 1 or
                dfile < sfile - 1 or
                drank > srank + 1 or
                drank < srank - 1)
                return false
            else
                return true;
        },
    }
    return false;
}

/// ensures all squares between source and dest are empty
fn ensureEmpty(position: Position, source: Coordinate, dest: Coordinate) bool {
    var iter = DirectionalIterator.init(source, dest);
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
            if (position.at(coord).isEmpty() or position.at(coord).affiliation().? == position.side_to_move.opponent()) {
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
    var iter = DirectionalIterator.init(position.kingCoord(), checkers[0]);
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
    var buffer: [32]Coordinate = undefined;
    const checkers = position.query(&buffer, .{
        .affiliation = position.side_to_move.opponent(),
        .target_coord = position.kingCoord(),
        .attacking = true,
    });
    if (checkers.len > 0) {
        return if (position.isMate())
            .ok_mate
        else
            .ok_check;
    }
    return .ok;
}

/// iterates over squares between two coords exclusive
const DirectionalIterator = struct {
    dest: Coordinate,
    at: Coordinate,
    delta_file: i8,
    delta_rank: i8,

    pub fn init(source: Coordinate, dest: Coordinate) DirectionalIterator {
        const rank_diff = dest.getRank().val() - source.getRank().val();
        const file_diff = dest.getFile().val() - source.getFile().val();
        const length = std.math.sqrt(@intCast(u8, rank_diff * rank_diff + file_diff * file_diff));
        const rank_delta = std.math.clamp(div(rank_diff, length), -1, 1);
        const file_delta = std.math.clamp(div(file_diff, length), -1, 1);
        return .{
            .dest = dest,
            .at = source,
            .delta_file = file_delta,
            .delta_rank = rank_delta,
        };
    }

    pub fn next(iter: *DirectionalIterator) ?Coordinate {
        if (!iter.at.offset(iter.delta_file, iter.delta_rank))
            return null;
        if (iter.at.value == iter.dest.value) return null;
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
/// std.math.absInt() errors when val is minInt()
/// as -minInt() is overflow by 1
/// we just return maxInt() in this case
/// off by one but it's fine don't worry about it
fn abs(val: i8) i8 {
    return std.math.absInt(val) catch std.math.maxInt(i8);
}

/// standard chess starting position
const starting_position: [64]Piece = blk_starting_position: {
    var squares: [64]Piece = [_]Piece{Piece.empty()} ** 64;
    // helper to get pieces on the back ranks
    const back_rank = struct {
        const sequence: [8]Class = blk_sequence: {
            var classes: [8]Class = undefined;
            // back rank pieces from a to h
            classes[File.file_a.index()] = .rook;
            classes[File.file_b.index()] = .knight;
            classes[File.file_c.index()] = .bishop;
            classes[File.file_d.index()] = .queen;
            classes[File.file_e.index()] = .king;
            classes[File.file_f.index()] = .bishop;
            classes[File.file_g.index()] = .knight;
            classes[File.file_h.index()] = .rook;
            break :blk_sequence classes;
        };
        /// return white piece on back rank file `file`
        pub fn white(file: File) Piece {
            return Piece.init(sequence[file.index()], .white);
        }
        /// return black piece on back rank file `file`
        pub fn black(file: File) Piece {
            return Piece.init(sequence[file.index()], .black);
        }
    };

    const white_pawn = Piece.init(.pawn, .white);
    const black_pawn = Piece.init(.pawn, .black);
    const white_back_rank = Affiliation.white.backRank();
    const black_back_rank = Affiliation.black.backRank();
    const white_second_rank = Affiliation.white.secondRank();
    const black_second_rank = Affiliation.black.secondRank();

    // iterate over files a to h (0 to 7)
    var file_iter = File.file_a.iterator();
    while (file_iter.next()) |file| {
        // back rank
        squares[Coordinate.from2d(file, white_back_rank).index()] = back_rank.white(file);
        squares[Coordinate.from2d(file, black_back_rank).index()] = back_rank.black(file);
        // pawns
        squares[Coordinate.from2d(file, white_second_rank).index()] = white_pawn;
        squares[Coordinate.from2d(file, black_second_rank).index()] = black_pawn;
    }
    break :blk_starting_position squares;
};
