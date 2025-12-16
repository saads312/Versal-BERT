`timescale 1ns / 1ps                                                                                                                             
                                                                                                                                                
module noc_self_output_control (                                                                                                                 
    input wire clk,                                                                                                                              
    input wire rstn,                                                                                                                             
                                                                                                                                                
    // External control                                                                                                                          
    input wire start,                                                                                                                            
    output reg done,                                                                                                                             
    output reg error,                                                                                                                            
                                                                                                                                                
    // DMA control outputs                                                                                                                       
    output reg start_dma_attn,      // Read attention output                                                                                     
    output reg start_dma_weight,    // Read W_self_output weight                                                                                 
    output reg start_dma_residual,  // Read residual                                                                                             
    output reg start_dma_out,       // Write final output                                                                                        
                                                                                                                                                
    // DMA status inputs                                                                                                                         
    input wire dma_attn_done,                                                                                                                    
    input wire dma_weight_done,                                                                                                                  
    input wire dma_residual_done,                                                                                                                
    input wire dma_out_done,                                                                                                                     
    input wire dma_attn_error,                                                                                                                   
    input wire dma_weight_error,                                                                                                                 
    input wire dma_residual_error,                                                                                                               
    input wire dma_out_error,                                                                                                                    
                                                                                                                                                
    // Compute control                                                                                                                           
    output reg start_compute,                                                                                                                    
    input wire compute_done                                                                                                                      
); 

// State encoding                                                                                                                                
localparam IDLE             = 4'd0;                                                                                                              
// Processing states                                                                                                                             
localparam LOAD_ATTN        = 4'd1;                                                                                                              
localparam LOAD_WEIGHT      = 4'd2;                                                                                                              
localparam LOAD_RESIDUAL    = 4'd3;                                                                                                              
localparam COMPUTE          = 4'd4;                                                                                                              
localparam WRITE_OUTPUT     = 4'd5;                                                                                                              
// Terminal states                                                                                                                               
localparam DONE_STATE       = 4'd6;                                                                                                              
localparam ERROR_STATE      = 4'd7;                                                                                                              
                                                                                                                                                
reg [3:0] state, prev_state;  

// State register                                                                                                                                
reg reset_logged;                                                                                                                                
always @(posedge clk) begin                                                                                                                      
    if (!rstn) begin                                                                                                                             
        state <= IDLE;                                                                                                                           
        prev_state <= IDLE;                                                                                                                      
        if (!reset_logged) begin                                                                                                                 
            $display("[%t] SELF_OUTPUT FSM RESET", $time);                                                                                       
            reset_logged <= 1'b1;                                                                                                                
        end                                                                                                                                      
    end else begin                                                                                                                               
        reset_logged <= 1'b0;                                                                                                                    
        prev_state <= state;                                                                                                                     
        case (state)                                                                                                                             
            IDLE: begin                                                                                                                          
                if (start) begin                                                                                                                 
                    state <= LOAD_ATTN;                                                                                                          
                    $display("[%t] SELF_OUTPUT FSM: IDLE->LOAD_ATTN", $time);                                                                    
                end                                                                                                                              
            end                                                                                                                                  
                                                                                                                                                                                                             
            // PROCESSING STATES                                                                                                                                                                                 
            LOAD_ATTN: begin                                                                                                                     
                if (dma_attn_error) begin                                                                                                        
                    state <= ERROR_STATE;                                                                                                        
                    $display("[%t] SELF_OUTPUT FSM: LOAD_ATTN->ERROR", $time);                                                                   
                end else if (dma_attn_done) begin                                                                                                
                    state <= LOAD_WEIGHT;                                                                                                        
                    $display("[%t] SELF_OUTPUT FSM: LOAD_ATTN->LOAD_WEIGHT", $time);                                                             
                end                                                                                                                              
            end                                                                                                                                  
                                                                                                                                                
            LOAD_WEIGHT: begin                                                                                                                   
                if (dma_weight_error) begin                                                                                                      
                    state <= ERROR_STATE;                                                                                                        
                    $display("[%t] SELF_OUTPUT FSM: LOAD_WEIGHT->ERROR", $time);                                                                 
                end else if (dma_weight_done) begin                                                                                              
                    state <= LOAD_RESIDUAL;                                                                                                      
                    $display("[%t] SELF_OUTPUT FSM: LOAD_WEIGHT->LOAD_RESIDUAL", $time);                                                         
                end                                                                                                                              
            end                                                                                                                                  
                                                                                                                                                
            LOAD_RESIDUAL: begin                                                                                                                 
                if (dma_residual_error) begin                                                                                                    
                    state <= ERROR_STATE;                                                                                                        
                    $display("[%t] SELF_OUTPUT FSM: LOAD_RESIDUAL->ERROR", $time);                                                               
                end else if (dma_residual_done) begin                                                                                            
                    state <= COMPUTE;                                                                                                            
                    $display("[%t] SELF_OUTPUT FSM: LOAD_RESIDUAL->COMPUTE", $time);                                                             
                end                                                                                                                              
            end                                                                                                                                  
                                                                                                                                                
            COMPUTE: begin                                                                                                                       
                if (compute_done) begin                                                                                                          
                    state <= WRITE_OUTPUT;                                                                                                       
                    $display("[%t] SELF_OUTPUT FSM: COMPUTE->WRITE_OUTPUT", $time);                                                              
                end                                                                                                                              
            end                                                                                                                                  
                                                                                                                                                
            WRITE_OUTPUT: begin                                                                                                                  
                if (dma_out_error) begin                                                                                                         
                    state <= ERROR_STATE;                                                                                                        
                    $display("[%t] SELF_OUTPUT FSM: WRITE_OUTPUT->ERROR", $time);                                                                
                end else if (dma_out_done) begin                                                                                                 
                    state <= DONE_STATE;                                                                                                         
                    $display("[%t] SELF_OUTPUT FSM: WRITE_OUTPUT->DONE", $time);                                                                 
                end                                                                                                                              
            end                                                                                                                                  
                                                                                                                                                                                                                
            // TERMINAL STATES                                                                                                                                                                                    
            DONE_STATE: begin                                                                                                                    
                if (!start) begin                                                                                                                
                    state <= IDLE;                                                                                                               
                    $display("[%t] SELF_OUTPUT FSM: DONE->IDLE", $time);                                                                         
                end                                                                                                                              
            end                                                                                                                                  
                                                                                                                                                
            ERROR_STATE: begin                                                                                                                   
                if (!start) begin                                                                                                                
                    state <= IDLE;                                                                                                               
                    $display("[%t] SELF_OUTPUT FSM: ERROR->IDLE", $time);                                                                        
                end                                                                                                                              
            end                                                                                                                                  
                                                                                                                                                
            default: begin                                                                                                                       
                state <= IDLE;                                                                                                                   
                $display("[%t] SELF_OUTPUT FSM: UNKNOWN->IDLE", $time);                                                                          
            end                                                                                                                                  
        endcase                                                                                                                                  
    end                                                                                                                                          
end 

// Output logic - pulse DMA/compute starts on state transitions here                                                                                  
always @(posedge clk) begin                                                                                                                      
    if (!rstn) begin                                                                                                                             
        start_dma_attn <= 1'b0;                                                                                                                  
        start_dma_weight <= 1'b0;                                                                                                                
        start_dma_residual <= 1'b0;                                                                                                              
        start_dma_out <= 1'b0;                                                                                                                   
        start_compute <= 1'b0;                                                                                                                   
        done <= 1'b0;                                                                                                                            
        error <= 1'b0;                                                                                                                           
    end else begin                                                                                                                               
        // Default - pulses are one clock cycle                                                                                                  
        start_dma_attn <= 1'b0;                                                                                                                  
        start_dma_weight <= 1'b0;                                                                                                                
        start_dma_residual <= 1'b0;                                                                                                              
        start_dma_out <= 1'b0;                                                                                                                   
        start_compute <= 1'b0;                                                                                                                   
                                                                                                                                                
        // Pulse start signals on state entry, load attention output                                                                                                                                                                                                               
        if (state == LOAD_ATTN && prev_state != LOAD_ATTN) begin                                                                                 
            start_dma_attn <= 1'b1;                                                                                                              
            $display("[%t] SELF_OUTPUT FSM: Pulsing start_dma_attn", $time);                                                                     
        end                                                                                                                                      
                                                                                                                                                
        // Load weight                                                                                                                           
        if (state == LOAD_WEIGHT && prev_state != LOAD_WEIGHT) begin                                                                             
            start_dma_weight <= 1'b1;                                                                                                            
            $display("[%t] SELF_OUTPUT FSM: Pulsing start_dma_weight", $time);                                                                   
        end                                                                                                                                      
                                                                                                                                                
        // Load residual                                                                                                                         
        if (state == LOAD_RESIDUAL && prev_state != LOAD_RESIDUAL) begin                                                                         
            start_dma_residual <= 1'b1;                                                                                                          
            $display("[%t] SELF_OUTPUT FSM: Pulsing start_dma_residual", $time);                                                                 
        end                                                                                                                                      
                                                                                                                                                
        // Start compute and write DMA at compute entry                                                                                          
        // The pipeline here: mm->requant->mat_add->layernorm->requant->write_dma, is streaming, so write DMA must be ready before data arrives                                                                                        
        if (state == COMPUTE && prev_state != COMPUTE) begin                                                                                     
            start_compute <= 1'b1;                                                                                                               
            start_dma_out <= 1'b1;                                                                                                               
            $display("[%t] SELF_OUTPUT FSM: Pulsing start_compute and start_dma_out", $time);                                                    
        end                                                                                                                                      
                                                                                                                                                
        // Status outputs                                                                                                                        
        done <= (state == DONE_STATE);                                                                                                           
        error <= (state == ERROR_STATE);                                                                                                         
    end                                                                                                                                          
end                                                                                                                                                                                                                                                                                      


                                                                                                                                                  
 endmodule