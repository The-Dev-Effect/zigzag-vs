const std = @import("std");
const Api = @import("api.zig");
const ApiTypes = @import("api_modules.zig");

const RndGen = std.rand.DefaultPrng;

const EnemyType = enum {
    FISH,
    ROOMBA, 
    AMOEBA,
};

// const Object = struct { object_type: ObjectType, x: f32 = 0, y: f32 = 0, spr: u32 = 4, draw: bool = true };

const FishState = struct {
    saw_bubbles: bool = false
};

const RoombaState = struct {
    visible: bool = true
};

const Enemy = struct { enemy_type: EnemyType, x: f32 = 0, y: f32 = 0, spr: u32 = 4, draw: bool = true,
    fish_state: FishState = .{}, roomba_state: RoombaState = .{} };


const NUM_ENEMIES = 5000;

fn makeEnemy() Enemy {
    return Enemy{ .enemy_type = EnemyType.FISH, .x = 0.0, .y = 0.0, .spr = 4, .draw = true };
}

fn pointInBox(x: f32, y: f32, bx: f32, by: f32, bw: f32, bh: f32) bool {
    return (x >= bx and x <= bx + bw and y >= by and y <= by + bh);
}

fn boxIntersect(x1: f32, y1: f32, w1: f32, h1: f32, x2: f32, y2: f32, w2: f32, h2: f32) bool {
    // Basically check if any of our points are within
    return (
    // box1 points in box2
        pointInBox(x1, y1, x2, y2, w2, h2) or
        pointInBox(x1 + w1, y1, x2, y2, w2, h2) or
        pointInBox(x1, y1 + h1, x2, y2, w2, h2) or
        pointInBox(x1 + w1, y1 + h1, x2, y2, w2, h2) or
        // box2 points in box1
        pointInBox(x2, y2, x1, y1, w1, h1) or
        pointInBox(x2 + w2, y2, x1, y1, w1, h1) or
        pointInBox(x2, y2 + h2, x1, y1, w1, h1) or
        pointInBox(x2 + w2, y2 + h2, x1, y1, w1, h1));
}

const AIUpdate = struct {
    dx: f32,
    dy: f32,
};

fn enemyAI(player_x: f32, player_y: f32, enemy: Enemy) AIUpdate {
    _ = player_x;
    _ = player_y;
    _ = enemy;
    return .{
        .dx = 0.1, .dy = -0.1
    };

}

const PlayerAnimation = struct {
    forward: bool = true,
    walk_cycle: u32 = 0, // 0 - 16 standing, 16 - 32 - left, 32 - 48 right.
};

pub const Game = struct {
    player_animation: PlayerAnimation = .{},
    x: f32 = 30.0,
    y: f32 = 30.0,
    sprite: u32 = 2,
    map_offset: u32 = 0,
    rnd: std.rand.DefaultPrng,
    randomize_count: u32 = 0,
    random_seed: u32 = 0,
    enemies: [NUM_ENEMIES]Enemy,

    pub fn init(api: *Api.Api) Game {
        var rnd = RndGen.init(0);

        // Build a map of grass.
        var x: u32 = 0;
        var y: u32 = 0;
        while (x < 256) {
            while (y < 256) {
                if (rnd.random().int(u8) % 10 == 0) {
                    api.mset(x, y, 1, 0);
                } else {
                    api.mset(x, y, 48, 0);
                }

                y += 1;
            }
            x += 1;
            y = 0;
        }

        var enemies = [_]Enemy{makeEnemy()} ** NUM_ENEMIES;

        // Place the birds on the grass.
        for (enemies) |*o| {
            // Don't place the birds on obstacles.
            const enemy_type: EnemyType = switch(rnd.random().int(u32) % 100) {
                0...70 => EnemyType.FISH,
                71...95 => EnemyType.ROOMBA,
                else => EnemyType.AMOEBA

            };
            o.*.enemy_type =enemy_type;

            while (true) {
                var o_x = rnd.random().int(u32) % 100;
                var o_y = rnd.random().int(u32) % 100;
                if (api.mget(o_x, o_y, 0) == 48) {
                    o.*.x = @intToFloat(f32, o_x) * 8.0 + 0.1;
                    o.*.y = @intToFloat(f32, o_y) * 8.0 + 0.1;
                    break;
                }
            }
        }

        return .{ .rnd = rnd, .enemies = enemies };
    }

    pub fn walkableTile(self: Game, api: *Api.Api, x: f32, y: f32) bool {
        _ = self;
        if (x < 0 or x >= 256 * 8 or y < 0 or y > 256 * 8) {
            return false;
        }
        const tx = @floatToInt(u32, std.math.floor(x / 8.0));
        const ty = @floatToInt(u32, std.math.floor(y / 8.0));

        const tile = api.mget(tx, ty, 0); // == 48; // only grass is walkable.

        // Only grass is walkable.
        return tile == 48;
    }

    pub fn worldMove(self: Game, api: *Api.Api, x: f32, y: f32, w: f32, h: f32, dx: *f32, dy: *f32) void {
        // Keep world moving, ta
        self.worldMovePoint(api, x, y, dx, dy);
        self.worldMovePoint(api, x + w, y, dx, dy);
        self.worldMovePoint(api, x, y + h, dx, dy);
        self.worldMovePoint(api, x + w, y + h, dx, dy);
    }

    pub fn worldMovePoint(self: Game, api: *Api.Api, x: f32, y: f32, dx: *f32, dy: *f32) void {
        // Right now we want to see if we can move a single point.
        // We will separate moves into first left and right and then up and down.

        // First attempt to left and right.
        if (dx.* > 0.0 and !self.walkableTile(api, x + dx.*, y)) {
            dx.* = 0.0;
        }
        if (dx.* < 0.0 and !self.walkableTile(api, x + dx.*, y)) {
            dx.* = 0.0;
        }

        // Now update and move right and left.
        if (dy.* > 0.0 and !self.walkableTile(api, x + dx.*, y + dy.*)) {
            dy.* = 0.0;
        }
        if (dy.* < 0.0 and !self.walkableTile(api, x + dx.*, y + dy.*)) {
            dy.* = 0.0;
        }
    }

    // pub fn updateEnemyAI(obj) void {

    // }

    fn moveSpeedEnemy() void { //

    }

    fn circleAttackEnemy() void {}

    pub fn update(self: *Game, api: *Api.Api) void {
        var dx: f32 = 0;
        var dy: f32 = 0;

        if (api.btn(ApiTypes.Button.RIGHT)) {
            dx = 1.0;
        }
        if (api.btn(ApiTypes.Button.LEFT)) {
            dx = -1.0;
        }
        if (api.btn(ApiTypes.Button.DOWN)) {
            dy = 1.0;
        }
        if (api.btn(ApiTypes.Button.UP)) {
            dy = -1.0;
        }

        // Our game objects are really 7x7 so they can fit into the cracks of the tile.
        self.worldMove(api, self.x, self.y, 7.0, 7.0, &dx, &dy);

        // Update the player animation state.

        if (dx != 0 or dy != 0) {
            self.player_animation.walk_cycle = 1 + (self.player_animation.walk_cycle + 1) % 48;
        } else {
            self.player_animation.walk_cycle = 0;
        }

        if (dy > 0.0) {
            self.player_animation.forward = true;
        } else if (dy < 0.0) {
            self.player_animation.forward = false;
        }

        self.x += dx;
        self.y += dy;

        for (self.enemies) |*o| {
            var info = enemyAI(self.x, self.y, o.*);
            //info.dx = (self.rnd.random().float(f32) - 0.5) * 4.0;
            //info.dy = (self.rnd.random().float(f32) - 0.5) * 4.0;

            //var target_x = self.x - 0; //o.*.x;
            //var target_y = self.y - 0; //o.*.y;

            //const scale = 1.0 / (std.math.sqrt(target_x * target_x + target_y * target_y) + 0.0001);

            //o_dx += target_x * scale;
            //o_dy += target_y * scale;

            self.worldMove(api, o.*.x, o.*.y, 7.0, 7.0, &info.dx, &info.dy);
            o.*.x += info.dx;
            o.*.y += info.dy;

            if (boxIntersect(self.x, self.y, 8.0, 8.0, o.*.x, o.*.y, 8.0, 8.0)) {
                o.*.spr = 5;
                o.*.draw = false;
            }
        }

        self.randomize_count = (self.randomize_count + 1) % 20;

        // Randomize.

        //if (self.randomize_count == 0) {
        //    self.random_seed = (self.random_seed + 1) % 3;
        //    var rnd = RndGen.init(self.random_seed);

        //    var x: u32 = 0;
        //    var y: u32 = 0;
        //    while (x < 256) {
        //        while (y < 256) {
        //            if (rnd.random().int(u8) % 10 == 0) {
        //                api.mset(x, y, 38 + rnd.random().int(u8) % 4, 1);
        //            } else {
        //                api.mset(x, y, 0, 1);
        //            }
        //            y += 1;
        //        }
        //        x += 1;
        //        y = 0;
        //    }
        //}

        api.camera(self.x - 64 - 4, self.y - 64 - 4);
    }

    pub fn draw(self: *Game, api: *Api.Api) void {
        // draw the map
        api.map(0, 0, 0, 0, 256, 256, 0);

        for (self.enemies) |o| {
            if (o.draw) {
                const spr: u32 = switch (o.enemy_type) {
                    EnemyType.FISH => 4,
                    EnemyType.ROOMBA => 8,
                    EnemyType.AMOEBA => 11

                };
                api.spr(spr, o.x, o.y, 8.0, 8.0);
            }
        }
        //api.map(0, 0, 0, 0, 256, 256, 1);
        self.drawRyan(api);
    }

    fn drawRyan(self: Game, api: *Api.Api) void {
        const walkdiff: u32 = switch (self.player_animation.walk_cycle) {
            0 => 1,
            1...24 => 0,
            else => 2,
        };

        const leftarmdiff: u32 = switch (self.player_animation.walk_cycle) {
            0 => 1,
            1...24 => 1,
            else => 0,
        };

        const rightarmdiff: u32 = switch (self.player_animation.walk_cycle) {
            0 => 0,
            1...24 => 0,
            else => 1,
        };
        const forwarddiff: u32 = switch (self.player_animation.forward) {
            true => 0,
            false => 1,
        };

        // draw the head.
        api.spr(50 + forwarddiff, self.x, self.y - 16.0, 8.0, 8.0);

        // The body
        api.spr(50 + 16, self.x, self.y - 8.0, 8.0, 8.0);

        // The arms.
        api.spr(48 + 16 + leftarmdiff, self.x - 8.0, self.y - 8.0, 8.0, 8.0);
        api.spr(52 + 16 + rightarmdiff, self.x + 8.0, self.y - 8.0, 8.0, 8.0);

        // The legs depend on the wlak cycle
        api.spr(49 + 16 * 2 + walkdiff, self.x, self.y, 8.0, 8.0);
    }
};
