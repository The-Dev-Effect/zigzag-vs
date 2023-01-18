const std = @import("std");
const Api = @import("api.zig");
const ApiTypes = @import("api_modules.zig");
const pow = std.math.pow;



const RndGen = std.rand.DefaultPrng;

const Object = struct { x: f32 = 0, y: f32 = 0, spr: u32 = 4, draw: bool = true, health: u32 = 5 };

const Bullet = struct { 
    x: f32 = 0,
    y: f32 = 0,
    vector: BulletVector = BulletVector{},
    spr: u32 = 36,
    draw: bool = false,
};

const BulletVector = struct {
    dx: f32 = 0,
    dy: f32 = 0,
};

const xpSprite = struct { x: f32 = 0, y: f32 = 0, spr: u32 = 38, draw: bool = false };

const xpCount = struct { x: f32 = 0, y: f32 = 0, spr: u32 = 54, draw: bool = false };

const bowlingball = struct { x: f32 = 0, y: f32 = 0, spr: u32 = 3, draw: bool = false };

//These numbers are way too large
//2^14
// const NUM_OBJECTS = 16384;
// const NUM_BULLETS = 500;
const NUM_OBJECTS = 500;
const NUM_BULLETS = 100;
const NUM_XP=100;
const BULLET_SPEED = 2.0;

fn make_bullet() Bullet {
    return Bullet{};
}
const MAX_HEALTH_SPRITE = 128;
const NUM_LEVELS = 10;

fn makeObject(draw: bool) Object {
    return Object{ .x = 0.0, .y = 0.0, .spr = 4, .draw = draw };
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

pub const Game = struct {
    x: f32 = 30.0,
    y: f32 = 30.0,
    sprite: u32 = 2,
    map_offset: u32 = 0,
    rnd: std.rand.DefaultPrng,
    randomize_count: u32 = 0,
    random_seed: u32 = 0,
    objects: [NUM_OBJECTS]Object,
    waveBar:[10]Object,
    frameCount: u32 = 0,
    waveNumber: u32 = 1,
    bullets: [NUM_BULLETS]Bullet = [_]Bullet{make_bullet()} ** NUM_BULLETS,
    last_bullet_idx: u32 = 0,


    player_health: u32 = 100,
    player_hurt: bool = false,
    xp: [NUM_XP]xpSprite,
    xpcounter: u32 = 0,
    level: u32=1,
    bowlingball:bowlingball,

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

        var objects = [_]Object{makeObject(false)} ** NUM_OBJECTS;

        // Place the birds on the grass.
        const currentWaveTotal = @floatToInt(i64, pow(f64, 2, 10));
        for (objects) |*o, indx| {
            if(indx >= currentWaveTotal){
                break;
            }
            // Don't place the birds on obstacles.
            while (true) {
                var o_x = rnd.random().int(u32) % 100;
                var o_y = rnd.random().int(u32) % 100;
                o.*.draw = true;
                if (api.mget(o_x, o_y, 0) == 48) {
                    o.*.x = @intToFloat(f32, o_x) * 8.0 + 0.1;
                    o.*.y = @intToFloat(f32, o_y) * 8.0 + 0.1;
                    break;
                }
            }
        }

        var waveBar = [_]Object{makeObject(true)} ** 10;
        for (waveBar) |*bar, bar_indx| {
            var bar_x = bar_indx;
            bar.*.x = @intToFloat(f32, bar_x) * 8;
            bar.*.y = -8.0;
        }

        var xpsprites = [_]xpSprite{.{}} ** NUM_XP;

        return .{ .rnd = rnd, .objects = objects, .waveBar = waveBar, .xp = xpsprites, .bowlingball = .{}};
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

    fn get_free_bullet_idx(self: *Game) u32 {
        var idx: u32 = 0;

        for (self.bullets) |b| {
            if (b.draw == false) {
                self.last_bullet_idx = 0;
                return idx;
            } else if (idx + 1 < NUM_BULLETS) {
                idx += 1;
            }
        }

        if(self.last_bullet_idx + 1 < 100) {
            self.last_bullet_idx += 1;
        } else {
            self.last_bullet_idx = 0;
        }
        return self.last_bullet_idx;
    }

    fn bullet_collision(self: *Game, bullet: Bullet, api: *Api.Api) bool {
        if (!self.walkableTile(api, bullet.x + bullet.vector.dx, bullet.y + bullet.vector.dy)){
            return true;
        }
        return false;
    }

    fn update_bullets(self: *Game, api: *Api.Api) void {
        //TODO: figure out how to copy an array.
        for (self.bullets) |*b, index| {
            if (!b.draw) {
                continue;
            }

            if (self.bullet_collision(self.bullets[index], api)) {
                b.*.draw = false;
                continue;
            }

            b.*.x += b.*.vector.dx;
            b.*.y += b.*.vector.dy;
        }
    }

    fn fireBullet(self: *Game, bulletVector: BulletVector, x: f32, y: f32) void {
        self.bullets[self.get_free_bullet_idx()] = Bullet{
            .x = x + bulletVector.dx,
            .y = y + bulletVector.dy,
            .vector = bulletVector,
            .draw = true
        };
    }

    pub fn update(self: *Game, api: *Api.Api) void {
        var bullet_v: BulletVector = BulletVector{};
        self.frameCount += 1;

        var dx: f32 = 0;
        var dy: f32 = 0;
        
        for (self.waveBar) |*bar, indx| {
            bar.*.x = @intToFloat(f32, indx) *  8 + self.x - 24;
            bar.*.y = self.y - 70;
        }
        //~every 3 seconds
        if(self.frameCount % 90 == 0){
           var bar_indx = 10 - (self.frameCount / 90); 
           self.waveBar[bar_indx].draw = false;
           if(bar_indx == 0){
             self.frameCount = 0;
             self.waveNumber += 1;
             if(self.waveNumber == 5){
                self.waveNumber = 1;
             }
            const currentWaveTotal = @floatToInt(i64, pow(f64, 2, @intToFloat(f64, self.waveNumber + 9)));
            for (self.objects) |*o, object_idx| {
                if(object_idx >= currentWaveTotal){
                    break;
                }
                o.*.draw = true;
            }
            for (self.waveBar) |*bar| {
                bar.*.draw = true;
            }
           }
        }

        self.update_bullets(api);

        if(self.player_health > 0) {
            
            if (api.btn(ApiTypes.Button.RIGHT)) {
                bullet_v.dx += BULLET_SPEED;
                dx = 1.0;
            }
            if (api.btn(ApiTypes.Button.LEFT)) {
                bullet_v.dx -= BULLET_SPEED;
                dx = -1.0;
            }
            if (api.btn(ApiTypes.Button.DOWN)) {
                bullet_v.dy += BULLET_SPEED;
                dy = 1.0;
            }
            if (api.btn(ApiTypes.Button.UP)) {
                bullet_v.dy -= BULLET_SPEED;
                dy = -1.0;
            }
            if (api.btn(ApiTypes.Button.A)){
                if (bullet_v.dx != 0 or bullet_v.dy != 0){
                    self.fireBullet(bullet_v, self.x, self.y);
                }
            
            }
        }
        
        // Our game objects are really 7x7 so they can fit into the cracks of the tile.
        self.worldMove(api, self.x, self.y, 7.0, 7.0, &dx, &dy);

        self.x += dx;
        self.y += dy;
        if (self.frameCount % 70 == 0){
            self.bowlingball.draw = !self.bowlingball.draw;
        }
        for (self.objects) |*o| {
            var o_dx = (self.rnd.random().float(f32) - 0.5) * 2.0;
            var o_dy = (self.rnd.random().float(f32) - 0.5) * 2.0;

            var target_x = self.x - o.*.x;
            var target_y = self.y - o.*.y;

            const scale = 1.0 / (std.math.sqrt(target_x * target_x + target_y * target_y) + 0.0001);

            o_dx += target_x * scale;
            o_dy += target_y * scale;

            self.worldMove(api, o.*.x, o.*.y, 7.0, 7.0, &o_dx, &o_dy);
            o.*.x += o_dx;
            o.*.y += o_dy;

            //An enemy has collided with the player! 
            if (o.*.draw and boxIntersect(self.x, self.y, 8.0, 8.0, o.*.x, o.*.y, 8.0, 8.0)) {
                //The player is damaged.
                if(self.player_health > 0) {
                    self.player_health -= 1;
                }
                self.player_hurt = true;
                // api.sfx(0);

                //Push enemy away in attempt to not immediately die
                o.*.x -= 3 * o_dx;
                o.*.y -= 3 * o_dy;
                
                //Also hurt the enemy. If the enemy is dead, spawn XP
                o.*.health -= 1;
                if(o.*.health <= 0) {
                    o.*.draw = false;
                    for(self.xp) |*xp| {
                        if(xp.*.draw == false){
                            xp.*.x = o.*.x;
                            xp.*.y = o.*.y;
                            xp.*.draw = true;
                            break;
                        }
                    }
                }  
            } else {
                self.player_hurt = false;
            }

            //The enemy has collided with the bowling ball
            if (o.*.draw and self.bowlingball.draw and boxIntersect(self.x + 10, self.y, 8.0, 8.0, o.*.x, o.*.y, 8.0, 8.0)) {
                //hurt the enemy. If the enemy is dead, spawn XP
                o.*.health -= 1;
                if(o.*.health <= 0) {
                    o.*.draw = false;
                    for(self.xp) |*xp| {
                        if(xp.*.draw == false){
                            xp.*.x = o.*.x;
                            xp.*.y = o.*.y;
                            xp.*.draw = true;
                            break;
                        }
                    }
                }  
            }
        }

        for (self.xp) |*xp| {
            if (xp.*.draw and boxIntersect(self.x, self.y, 8.0, 8.0, xp.*.x + 2, xp.*.y + 2, 4.0, 4.0)) {
                xp.*.draw = false;
                self.xpcounter += 1;
                if(self.xpcounter >= 10*self.level and self.level < NUM_LEVELS){
                    self.xpcounter = 0;
                    self.level += 1;
                    self.player_health = 100;
                }
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

        //draw waveBar
        for (self.waveBar) |bar| {
            if (bar.draw) {
                api.spr(bar.spr, bar.x, bar.y, 8.0, 8.0);
            }
        }

        for (self.objects) |o| {
            if (o.draw) {
                api.spr(o.spr, o.x, o.y, 8.0, 8.0);
            }
        }

        for (self.bullets) |b| {
            if(b.draw) {
                api.spr(b.spr, b.x, b.y, 8.0, 8.0);
            }
        }

        for (self.xp) |xp| {
            if (xp.draw) {
                api.spr(xp.spr, xp.x, xp.y, 8.0, 8.0);
            }
        }

        //Player sprite and score
        api.spr(self.sprite, self.x, self.y, 8.0, 8.0);
        api.spr(96 + self.xpcounter/10 % 10,self.x - 8, self.y + 8, 8.0, 8.0);
        api.spr(96 + self.xpcounter % 10,self.x, self.y + 8, 8.0, 8.0);

        //Player level
        api.spr(112,self.x - 30 ,self.y + 52, 8.0, 8.0);
        api.spr(113,self.x - 22 ,self.y + 52, 8.0, 8.0);
        api.spr(114,self.x - 14 ,self.y + 52, 8.0, 8.0);
        api.spr(96 + self.level/10 % 10,self.x - 6, self.y + 52, 8.0, 8.0);
        api.spr(96 + self.level % 10,self.x - -2, self.y + 52, 8.0, 8.0);

        //Player health bar
        var healthSpriteOffset = 6 - @floatToInt(u32, @intToFloat(f32,self.player_health) / 100.0 * 6);
        api.spr(MAX_HEALTH_SPRITE + healthSpriteOffset, self.x, self.y - 5, 8.0, 8.0);

        if(self.bowlingball.draw){
        api.spr(3, self.x + 10, self.y, 8.0, 8.0);
        }

        //api.map(0, 0, 0, 0, 256, 256, 1);
    }
};
