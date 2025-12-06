module vga_driver_to_frame_buf (
// CLOCK
    input CLOCK_50,
// SEG7
    output [6:0] HEX0,
    output [6:0] HEX1,
    output [6:0] HEX2,
    output [6:0] HEX3,
// KEY
    input [3:0] KEY,
// LED
    output [9:0] LEDR,
// SW
    input [9:0] SW,
// VGA
    output VGA_BLANK_N,
    output [7:0] VGA_B,
    output VGA_CLK,
    output [7:0] VGA_G,
    output VGA_HS,
    output [7:0] VGA_R,
    output VGA_SYNC_N,
    output VGA_VS
);

// HEX displays are turned off 
assign HEX0 = 7'h00;
assign HEX1 = 7'h00;
assign HEX2 = 7'h00;
assign HEX3 = 7'h00;


// Clock and reset signals 
wire clk = CLOCK_50;
wire rst = SW[0];  // SW[0] used as reset

// Debounced switches
wire [9:0] SW_db;
debounce_switches db(.clk(clk), .rst(rst), .SW(SW), .SW_db(SW_db));

// VGA frame signals
wire active_pixels;  // high when drawing active pixel
wire frame_done;     // high when frame is done
wire [9:0] x;        // current pixel x coordinate
wire [9:0] y;        // current pixel y coordinate

// Memory interface for VGA driver
reg [14:0] the_vga_draw_frame_write_mem_address;
reg [23:0] the_vga_draw_frame_write_mem_data;
reg the_vga_draw_frame_write_a_pixel;

// VGA frame driver instantiation
vga_frame_driver my_frame_driver(
    .clk(clk),
    .rst(rst),
    .active_pixels(active_pixels),
    .frame_done(frame_done),
    .x(x),
    .y(y),
    .VGA_BLANK_N(VGA_BLANK_N),
    .VGA_CLK(VGA_CLK),
    .VGA_HS(VGA_HS),
    .VGA_SYNC_N(VGA_SYNC_N),
    .VGA_VS(VGA_VS),
    .VGA_B(VGA_B),
    .VGA_G(VGA_G),
    .VGA_R(VGA_R),
    .the_vga_draw_frame_write_mem_address(the_vga_draw_frame_write_mem_address),
    .the_vga_draw_frame_write_mem_data(the_vga_draw_frame_write_mem_data),
    .the_vga_draw_frame_write_a_pixel(the_vga_draw_frame_write_a_pixel)
);

// Game constants and parameters
parameter PLAYER_COLOR = 24'hB8E2F4;
parameter PLAYER_WIDTH = 20;
parameter PLAYER_HEIGHT = 20;
parameter STEP_SIZE = 10'd10;
parameter PLAYER_MOVE_THRESHOLD = 21'd200_000;

parameter GREEN_ALIEN  = 24'h66FF00;
parameter PURPLE_ALIEN = 24'b100000000100000010000000;
parameter RED_ALIEN = 24'hFF0000;
parameter ALIEN_W = 20;
parameter ALIEN_H = 20;

parameter MOVE_THRESHOLD = 21'd500_000;
parameter BULLET_MOVE_THRESHOLD = 21'd300_000;
parameter ALIEN_BULLET_MOVE_TH = 21'd400_000;

parameter VGA_W = 640;
parameter VGA_H = 480;

// FSM states
parameter INIT = 4'd0;
parameter PLAYER_MOVE = 4'd1;
parameter ALIEN_MOVE = 4'd2;
parameter PLAYER_SHOOT = 4'd3;
parameter BULLET_MOVE = 4'd4;
parameter ALIEN_BULLETS = 4'd5;
parameter COLLISION = 4'd6;
parameter WIN_CHECK = 4'd7;
parameter DRAW = 4'd8;
parameter ERROR = 4'd9;

// Game state variables 
reg [9:0] player_x;
reg [9:0] player_y;
reg [20:0] player_move_timer;

reg [9:0] alien_position_x[29:0];
reg [9:0] alien_position_y[29:0];
reg alien_alive[29:0];

reg [20:0] move_timer;

reg win;
reg game_over;

// LED register (output driver)
reg [9:0] led_reg;
assign LEDR = led_reg;

// Player input signals (active low)
wire move_left = ~KEY[2];
wire move_right = ~KEY[0];
wire shoot = ~KEY[1];
reg shoot_prev;

// Player bullet variables
reg bullet_active;
reg [9:0]  bullet_x;
reg [9:0]  bullet_y;
reg [20:0] bullet_timer;

// Alien bullets variables
reg ab_act_0; reg [9:0] ab_x_0; reg [9:0] ab_y_0; reg [20:0] ab_t_0;
reg ab_act_1; reg [9:0] ab_x_1; reg [9:0] ab_y_1; reg [20:0] ab_t_1;
reg ab_act_2; reg [9:0] ab_x_2; reg [9:0] ab_y_2; reg [20:0] ab_t_2;
reg ab_act_3; reg [9:0] ab_x_3; reg [9:0] ab_y_3; reg [20:0] ab_t_3;
reg ab_act_4; reg [9:0] ab_x_4; reg [9:0] ab_y_4; reg [20:0] ab_t_4;

// LFSR for random alien bullet generation
reg [15:0] lfsr_reg;
wire [15:0] lfsr_next = { lfsr_reg[14:0], lfsr_reg[15] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10] };

// FSM state
reg [3:0] state;
integer i;

// Main FSM and game logic 
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        // Reset / initialization
        state <= INIT;
        lfsr_reg <= 16'hACE1;

        player_x <= 320;          // Start player in middle
        player_y <= 451;          // Start player near bottom
        player_move_timer <= 0;
        shoot_prev <= 1'b1;

        win <= 0;
        game_over <= 0;
        move_timer <= 0;

        bullet_active <= 0;
        bullet_x <= 0;
        bullet_y <= 0;
        bullet_timer <= 0;

        // Initialize aliens positions and alive status
        for (i = 0; i < 30; i=i+1) begin
            alien_alive[i] <= 1'b1;
            alien_position_x[i] <= (i % 10) * 60;
            if (i < 10) alien_position_y[i] <= 210;
            else if (i < 20) alien_position_y[i] <= 140;
            else alien_position_y[i] <= 54;
        end

        // Reset alien bullets
        ab_act_0 <= 0; ab_act_1 <= 0; ab_act_2 <= 0; ab_act_3 <= 0; ab_act_4 <= 0;
        ab_x_0 <= 0; ab_x_1 <= 0; ab_x_2 <= 0; ab_x_3 <= 0; ab_x_4 <= 0;
        ab_y_0 <= 0; ab_y_1 <= 0; ab_y_2 <= 0; ab_y_3 <= 0; ab_y_4 <= 0;
        ab_t_0 <= 0; ab_t_1 <= 0; ab_t_2 <= 0; ab_t_3 <= 0; ab_t_4 <= 0;

        // Turn off LEDs
        led_reg <= 10'd0;
    end else begin
        // Update LFSR for randomness
        lfsr_reg <= lfsr_next;

        // FSM transitions and logic
        case(state)
            INIT: state <= PLAYER_MOVE;

            // Player movement logic
            PLAYER_MOVE: begin
                if (player_move_timer >= PLAYER_MOVE_THRESHOLD) begin
                    player_move_timer <= 0;
                    if (move_left && player_x > STEP_SIZE) player_x <= player_x - STEP_SIZE;
                    if (move_right && player_x < (VGA_W-PLAYER_WIDTH-STEP_SIZE)) player_x <= player_x + STEP_SIZE;
                end else player_move_timer <= player_move_timer + 1'b1;
                state <= ALIEN_MOVE;
            end

            // Alien movement logic
            ALIEN_MOVE: begin
                if (move_timer >= MOVE_THRESHOLD) begin
                    move_timer <= 0;
                    for (i=0; i<30; i=i+1) begin
                        if (alien_alive[i]) begin
                            alien_position_x[i] <= alien_position_x[i] + 3;
                            if (alien_position_x[i] >= VGA_W) alien_position_x[i] <= 0;
                        end
                    end
                end else move_timer <= move_timer + 1'b1;
                state <= PLAYER_SHOOT;
            end

            // Handle player shooting
            PLAYER_SHOOT: begin
                if (shoot && !shoot_prev && !bullet_active) begin
                    bullet_active <= 1'b1;
                    bullet_x <= player_x + (PLAYER_WIDTH/2) - 1;
                    bullet_y <= player_y - 1;
                    bullet_timer <= 0;
                end
                shoot_prev <= shoot;
                state <= BULLET_MOVE;
            end

            // Move player bullet and check collisions
            BULLET_MOVE: begin
                if (bullet_active) begin
                    if (bullet_timer >= BULLET_MOVE_THRESHOLD) begin
                        bullet_timer <= 0;
                        if (bullet_y <= STEP_SIZE) bullet_active <= 0;
                        else bullet_y <= bullet_y - STEP_SIZE;
                        // check collision with aliens
                        if (bullet_active) begin
                            for (i=0; i<30; i=i+1) begin
                                if (alien_alive[i] && (bullet_x+4>alien_position_x[i]) &&
                                    (bullet_x<alien_position_x[i]+ALIEN_W) &&
                                    (bullet_y+8>alien_position_y[i]) &&
                                    (bullet_y<alien_position_y[i]+ALIEN_H)) begin
                                    alien_alive[i] <= 0;
                                    bullet_active <= 0;
                                end
                            end
                        end
                    end else bullet_timer <= bullet_timer + 1'b1;
                end
                state <= ALIEN_BULLETS;
            end

            // Move alien bullets and check collisions
            ALIEN_BULLETS: begin
                for (i=0; i<5; i=i+1) begin
                    case(i)
                        // Bullet movement logic for each bullet
                        0: if (ab_act_0) begin if (ab_t_0>=ALIEN_BULLET_MOVE_TH) begin ab_t_0<=0; ab_y_0<=ab_y_0+STEP_SIZE; if(ab_y_0>=VGA_H) ab_act_0<=0; if((ab_x_0+4>player_x)&&(ab_x_0<player_x+PLAYER_WIDTH)&&(ab_y_0+8>player_y)&&(ab_y_0<player_y+PLAYER_HEIGHT)) begin game_over<=1; ab_act_0<=0; end end else ab_t_0<=ab_t_0+1; end
                        1: if (ab_act_1) begin if (ab_t_1>=ALIEN_BULLET_MOVE_TH) begin ab_t_1<=0; ab_y_1<=ab_y_1+STEP_SIZE; if(ab_y_1>=VGA_H) ab_act_1<=0; if((ab_x_1+4>player_x)&&(ab_x_1<player_x+PLAYER_WIDTH)&&(ab_y_1+8>player_y)&&(ab_y_1<player_y+PLAYER_HEIGHT)) begin game_over<=1; ab_act_1<=0; end end else ab_t_1<=ab_t_1+1; end
                        2: if (ab_act_2) begin if (ab_t_2>=ALIEN_BULLET_MOVE_TH) begin ab_t_2<=0; ab_y_2<=ab_y_2+STEP_SIZE; if(ab_y_2>=VGA_H) ab_act_2<=0; if((ab_x_2+4>player_x)&&(ab_x_2<player_x+PLAYER_WIDTH)&&(ab_y_2+8>player_y)&&(ab_y_2<player_y+PLAYER_HEIGHT)) begin game_over<=1; ab_act_2<=0; end end else ab_t_2<=ab_t_2+1; end
                        3: if (ab_act_3) begin if (ab_t_3>=ALIEN_BULLET_MOVE_TH) begin ab_t_3<=0; ab_y_3<=ab_y_3+STEP_SIZE; if(ab_y_3>=VGA_H) ab_act_3<=0; if((ab_x_3+4>player_x)&&(ab_x_3<player_x+PLAYER_WIDTH)&&(ab_y_3+8>player_y)&&(ab_y_3<player_y+PLAYER_HEIGHT)) begin game_over<=1; ab_act_3<=0; end end else ab_t_3<=ab_t_3+1; end
                        4: if (ab_act_4) begin if (ab_t_4>=ALIEN_BULLET_MOVE_TH) begin ab_t_4<=0; ab_y_4<=ab_y_4+STEP_SIZE; if(ab_y_4>=VGA_H) ab_act_4<=0; if((ab_x_4+4>player_x)&&(ab_x_4<player_x+PLAYER_WIDTH)&&(ab_y_4+8>player_y)&&(ab_y_4<player_y+PLAYER_HEIGHT)) begin game_over<=1; ab_act_4<=0; end end else ab_t_4<=ab_t_4+1; end
                    endcase
                end
                state <= COLLISION;
            end

            // Collision check between player and aliens
            COLLISION: begin
                for (i=0; i<30; i=i+1) begin
                    if (alien_alive[i] &&
                        player_x < alien_position_x[i]+ALIEN_W &&
                        player_x+PLAYER_WIDTH > alien_position_x[i] &&
                        player_y < alien_position_y[i]+ALIEN_H &&
                        player_y+PLAYER_HEIGHT > alien_position_y[i])
                        game_over <= 1;
                end
                state <= WIN_CHECK;
            end

            // Check if player has won
            WIN_CHECK: begin
                win <= 1;
                for (i=0; i<30; i=i+1)
                    if (alien_alive[i]) win <= 0;
                state <= DRAW;
            end

            // Draw state, cycles back to player move
            DRAW: state <= PLAYER_MOVE;

            // Error state, keeps system in error and lights LED
            ERROR: begin
                state <= ERROR;
                led_reg[9] <= 1'b1; // light error LED
            end
        endcase

        // Catch invalid states
        if (state > ERROR) begin
            state <= ERROR;
            led_reg[9] <= 1'b1;
        end

        // Randomly spawn alien bullets based on LFSR
        for (i=0; i<30; i=i+1) begin
            if (alien_alive[i] && lfsr_reg[11:0]==(i+lfsr_reg[15:12])) begin
                if (!ab_act_0) begin ab_act_0<=1; ab_x_0<=alien_position_x[i]+ALIEN_W/2-1; ab_y_0<=alien_position_y[i]+ALIEN_H; ab_t_0<=0;
                end else if (!ab_act_1) begin ab_act_1<=1; ab_x_1<=alien_position_x[i]+ALIEN_W/2-1; ab_y_1<=alien_position_y[i]+ALIEN_H; ab_t_1<=0;
                end else if (!ab_act_2) begin ab_act_2<=1; ab_x_2<=alien_position_x[i]+ALIEN_W/2-1; ab_y_2<=alien_position_y[i]+ALIEN_H; ab_t_2<=0;
                end else if (!ab_act_3) begin ab_act_3<=1; ab_x_3<=alien_position_x[i]+ALIEN_W/2-1; ab_y_3<=alien_position_y[i]+ALIEN_H; ab_t_3<=0;
                end else if (!ab_act_4) begin ab_act_4<=1; ab_x_4<=alien_position_x[i]+ALIEN_W/2-1; ab_y_4<=alien_position_y[i]+ALIEN_H; ab_t_4<=0;
                end
            end
        end
    end
end

// VGA drawing logic 
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        the_vga_draw_frame_write_mem_address <= 0;
        the_vga_draw_frame_write_mem_data <= 0;
        the_vga_draw_frame_write_a_pixel <= 0;
    end else if (active_pixels) begin
        // Default background
        the_vga_draw_frame_write_mem_data <= 24'h000020;
        the_vga_draw_frame_write_a_pixel <= 1;

        // Draw WIN/Lose screens
        if (win) begin
            // Drawing W I N letters
            if ((x >= 20 && x < 40 && y >= 60 && y < 180) ||
                (x >= 80 && x < 100 && y >= 60 && y < 180) ||
                (x >= 140 && x < 160 && y >= 60 && y < 180) ||
                (x >= 20 && x < 160 && y >= 160 && y < 180))
                the_vga_draw_frame_write_mem_data <= 24'hB8E2F4;
            else if ((x >= 200 && x < 260 && y >= 60 && y < 80) ||
                     (x >= 200 && x < 260 && y >= 160 && y < 180) ||
                     (x >= 225 && x < 235 && y >= 60 && y < 180))
                the_vga_draw_frame_write_mem_data <= 24'hB8E2F4;
            else if ((x >= 300 && x < 320 && y >= 60 && y < 180) ||
                     (x >= 320 && x < 380 && y >= 60 && y < 80) ||
                     (x >= 380 && x < 400 && y >= 60 && y < 180))
                the_vga_draw_frame_write_mem_data <= 24'hB8E2F4;
        end else if (game_over) begin
            // Drawing L O S E letters
            if ((x >= 20 && x < 40 && y >= 60 && y < 180) ||
                (x >= 20 && x < 100 && y >= 160 && y < 180))
                the_vga_draw_frame_write_mem_data <= 24'hFF0000;
            else if ((x >= 120 && x < 140 && y >= 60 && y < 180) ||
                     (x >= 180 && x < 200 && y >= 60 && y < 180) ||
                     (x >= 140 && x < 180 && y >= 60 && y < 80) ||
                     (x >= 140 && x < 180 && y >= 160 && y < 180))
                the_vga_draw_frame_write_mem_data <= 24'hFF0000;
            else if ((x >= 220 && x < 300 && y >= 60 && y < 80) ||
                     (x >= 220 && x < 300 && y >= 110 && y < 130) ||
                     (x >= 220 && x < 300 && y >= 160 && y < 180) ||
                     (x >= 220 && x < 240 && y >= 60 && y < 120) ||
                     (x >= 280 && x < 300 && y >= 120 && y < 180))
                the_vga_draw_frame_write_mem_data <= 24'hFF0000;
            else if ((x >= 320 && x < 340 && y >= 60 && y < 180) ||
                     (x >= 340 && x < 400 && y >= 60 && y < 80) ||
                     (x >= 340 && x < 380 && y >= 110 && y < 130) ||
                     (x >= 340 && x < 400 && y >= 160 && y < 180))
                the_vga_draw_frame_write_mem_data <= 24'hFF0000;
        end else begin
            // Draw player, aliens, bullets
            // Player
            if ((x>=player_x)&&(x<player_x+PLAYER_WIDTH)&&(y>=player_y)&&(y<player_y+PLAYER_HEIGHT))
                the_vga_draw_frame_write_mem_data <= PLAYER_COLOR;

            // Aliens
            for (i=0; i<30; i=i+1) begin
                if (alien_alive[i] && (x>=alien_position_x[i])&&(x<alien_position_x[i]+ALIEN_W)&&
                    (y>=alien_position_y[i])&&(y<alien_position_y[i]+ALIEN_H))
                    the_vga_draw_frame_write_mem_data <= (i<10)?GREEN_ALIEN:(i<20)?PURPLE_ALIEN:RED_ALIEN;
            end

            // Player bullet
            if (bullet_active && (x>=bullet_x)&&(x<bullet_x+4)&&(y>=bullet_y)&&(y<bullet_y+8))
                the_vga_draw_frame_write_mem_data <= 24'hFFFFFF;

            // Alien bullets
            if (ab_act_0 && (x>=ab_x_0)&&(x<ab_x_0+4)&&(y>=ab_y_0)&&(y<ab_y_0+8)) the_vga_draw_frame_write_mem_data <= 24'hFF00FF;
            if (ab_act_1 && (x>=ab_x_1)&&(x<ab_x_1+4)&&(y>=ab_y_1)&&(y<ab_y_1+8)) the_vga_draw_frame_write_mem_data <= 24'hFF00FF;
            if (ab_act_2 && (x>=ab_x_2)&&(x<ab_x_2+4)&&(y>=ab_y_2)&&(y<ab_y_2+8)) the_vga_draw_frame_write_mem_data <= 24'hFF00FF;
            if (ab_act_3 && (x>=ab_x_3)&&(x<ab_x_3+4)&&(y>=ab_y_3)&&(y<ab_y_3+8)) the_vga_draw_frame_write_mem_data <= 24'hFF00FF;
            if (ab_act_4 && (x>=ab_x_4)&&(x<ab_x_4+4)&&(y>=ab_y_4)&&(y<ab_y_4+8)) the_vga_draw_frame_write_mem_data <= 24'hFF00FF;
        end
    end else the_vga_draw_frame_write_a_pixel <= 0;
end

endmodule
