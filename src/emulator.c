#include <stdio.h>
#include <stdlib.h>

typedef enum registers {R0=0,R1=1,R2=2,R3=3,R4=4,R5=5,R6=6,SP=6,R7=7,PC=7,R8=8,PSW=8} Register;

typedef enum instruction_codes {
  HALT = 0x00,
  INT = 0x10,
  IRET = 0x20,
  CALL = 0x30,
  RET = 0x40,
  JMP = 0x50,
  JEQ = 0x51,
  JNE = 0x52,
  JGT = 0x53,
  XCHG = 0x60,
  ADD = 0x70,
  SUB = 0x71,
  MUL = 0x72,
  DIV = 0x73,
  CMP = 0x74,
  NOT = 0x80,
  AND = 0x81,
  OR = 0x82,
  XOR = 0x83,
  TEST = 0x84,
  SHL = 0x90,
  SHR = 0x91,
  LDR = 0xA0,
  STR = 0xB0,
  INVALID_INSTRUCTION = 0xC0,
} InstructionCode;

typedef enum update_type
{
  NO_UPDATE=0,
  PRE_DECREASE,
  PRE_INCREASE,
  POST_DECREASE,
  POST_INCREASE,
} UpdateType;

typedef enum addressing_type
{
  IMMEDIATE=0,
  REG_DIR,
  REG_IND,
  REG_IND_WITH_ADD,
  MEMORY,
  REG_DIR_WITH_ADD,
} AddresingType;

typedef struct System
{
    unsigned char memory_vector[1<<16];
    short registers[9];
} System;

void registerToBinary(short reg,char binary_register[20])
{
  binary_register[0]='0';
  binary_register[1]='b';
  for(int i=2;i<18;i++)
  {
    binary_register[i]=((reg>>(17-i))&1)+'0';
  }
  binary_register[18]='\0';
}

void printSystemState(System system)
{
  char binary_psw[19];
  registerToBinary(system.registers[PSW],binary_psw);
  printf("Emulated processor executed halt instruction\n");
  printf("Emulated processor state: psw=%s\nr0=0x%04x\tr1=0x%04x\tr2=0x%04x\tr3=0x%04x\nr4=0x%04x\tr5=0x%04x\tr6=0x%04x\tr7=0x%04x\n",binary_psw,(unsigned short)(system.registers[0]),(unsigned short)(system.registers[1]),(unsigned short)(system.registers[2]),(unsigned short)(system.registers[3]),(unsigned short)(system.registers[4]),(unsigned short)(system.registers[5]),(unsigned short)(system.registers[6]),(unsigned short)(system.registers[7]));
}


int main(int argc, char* argv[]) {
    if (argc < 2 ) { printf("Error: Expected format is \"./emulator hex_fajl\"\n"); exit(1);
    }
    FILE *hex_file = fopen(argv[1], "r");
    if (!hex_file) 
    { 
      printf("Error: Could not open input file\n"); exit(1);
    }
    System system;
    int number;
    int location=0;
    char new_line;
    while (!feof(hex_file)) {
      fscanf(hex_file,"%x:",&location);
      for(int i=0;i<8;i++)
      {
          fscanf(hex_file,"%hhx%c",&(system.memory_vector[location+i]),&new_line);
          if(new_line=='\n')
          {
            break;
          }
          //MOZDA TREBA OVDE ELSE ZA EOF
      }
    }

    system.registers[PC]=((short*)(system.memory_vector))[0];
    system.registers[SP]=0;
    system.registers[PSW]=0;

    while(1)
    {
      unsigned char instruction=system.memory_vector[system.registers[PC]++];
      char reg_byte,addr_mode_byte,data_high,data_low;
      Register regD,regS;
      switch(instruction)
      {
        case HALT:
          printSystemState(system);
          exit(0);
          break;
        case INT:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          if((reg_byte&0x0F==0x0F) && (regD>=0 && regD<=8))
          {
            //OVAJ DEO NIJE U PDF-U,ALI BI TREBAO DA BUDE??
            system.memory_vector[--system.registers[SP]]=system.registers[PC]>>8;
            system.memory_vector[--system.registers[SP]]=system.registers[PC]&0x00FF;
            //OVAJ DEO JE U PDF-U
            system.memory_vector[--system.registers[SP]]=system.registers[PSW]>>8;
            system.memory_vector[--system.registers[SP]]=system.registers[PSW]&0x00FF;
            system.registers[PC]=((short)(system.memory_vector[(system.registers[regD]%8)*2+1]))<<8|system.memory_vector[(system.registers[regD]%8)*2];
            //*((short*)(&(system.memory_vector[(system.registers[regD]%8)*2])));
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case IRET:
          system.registers[PSW]=*((short*)(&(system.memory_vector[system.registers[SP]])));
          system.registers[SP]+=2;
          system.registers[PC]=*((short*)(&(system.memory_vector[system.registers[SP]])));
          system.registers[SP]+=2;
          break;
        case CALL:
          reg_byte=system.memory_vector[system.registers[PC]++];
          addr_mode_byte=system.memory_vector[system.registers[PC]++];
          regS=reg_byte&0x0F;
          AddresingType addressingType=addr_mode_byte&0x0F;
          UpdateType updateType=addr_mode_byte>>4;
          
          switch(addressingType)
          {
            case IMMEDIATE:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.memory_vector[--system.registers[SP]]=system.registers[PC]>>8;
                system.memory_vector[--system.registers[SP]]=system.registers[PC]&0x00FF;
                system.registers[PC]=((short)data_high)<<8|data_low;
              }
              break;
            case MEMORY:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.memory_vector[--system.registers[SP]]=system.registers[PC]>>8;
                system.memory_vector[--system.registers[SP]]=system.registers[PC]&0x00FF;
                system.registers[PC]=*((short*)(&(system.memory_vector[((short)data_high)<<8|data_low])));
              }
              break;
            case REG_DIR:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.memory_vector[--system.registers[SP]]=system.registers[PC]>>8;
                system.memory_vector[--system.registers[SP]]=system.registers[PC]&0x00FF;
                system.registers[PC]=system.registers[regS];
              }
              break;
            case REG_DIR_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.memory_vector[--system.registers[SP]]=system.registers[PC]>>8;
                system.memory_vector[--system.registers[SP]]=system.registers[PC]&0x00FF;
                system.registers[PC]=system.registers[regS]+(((short)data_high)<<8|data_low);
              }
              break;
            case REG_IND:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.memory_vector[--system.registers[SP]]=system.registers[PC]>>8;
                system.memory_vector[--system.registers[SP]]=system.registers[PC]&0x00FF;
                system.registers[PC]=*((short*)(&system.memory_vector[(system.registers[regS])]));
              }
              break;
            case REG_IND_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.memory_vector[--system.registers[SP]]=system.registers[PC]>>8;
                system.memory_vector[--system.registers[SP]]=system.registers[PC]&0x00FF;
                system.registers[PC]=*((short*)(&system.memory_vector[(system.registers[regS]+(((short)data_high)<<8|data_low))]));
              }
              break;
          }
          break;
        case RET:
          system.registers[PC]=*((short*)(&(system.memory_vector[system.registers[SP]])));
          system.registers[SP]+=2;
          break;
        case JMP:
          reg_byte=system.memory_vector[system.registers[PC]++];
          addr_mode_byte=system.memory_vector[system.registers[PC]++];
          regS=reg_byte&0x0F;
          addressingType=addr_mode_byte&0x0F;
          updateType=addr_mode_byte>>4;
          
          switch(addressingType)
          {
            case IMMEDIATE:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.registers[PC]=((short)data_high)<<8|data_low;
              }
              break;
            case MEMORY:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.registers[PC]=*((short*)(&(system.memory_vector[((short)data_high)<<8|data_low])));
              }
              break;
            case REG_DIR:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.registers[PC]=system.registers[regS];
              }
              break;
            case REG_DIR_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.registers[PC]=system.registers[regS]+(((short)data_high)<<8|data_low);
              }
              break;
            case REG_IND:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.registers[PC]=*((short*)(&system.memory_vector[(system.registers[regS])]));
              }
              break;
            case REG_IND_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.registers[PC]=*((short*)(&system.memory_vector[system.registers[regS]+(((short)data_high)<<8|data_low)]));
              }
              break;
          }
          break;
        case JEQ:
          reg_byte=system.memory_vector[system.registers[PC]++];
          addr_mode_byte=system.memory_vector[system.registers[PC]++];
          regS=reg_byte&0x0F;
          addressingType=addr_mode_byte&0x0F;
          updateType=addr_mode_byte>>4;
          
          switch(addressingType)
          {
            case IMMEDIATE:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(system.registers[PSW]&1)
                  system.registers[PC]=((short)data_high)<<8|data_low;
              }
              break;
            case MEMORY:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(system.registers[PSW]&1)
                  system.registers[PC]=*((short*)(&(system.memory_vector[((short)data_high)<<8|data_low])));
              }
              break;
            case REG_DIR:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(system.registers[PSW]&1)
                  system.registers[PC]=system.registers[regS];
              }
              break;
            case REG_DIR_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(system.registers[PSW]&1)
                  system.registers[PC]=system.registers[regS]+(((short)data_high)<<8|data_low);
              }
              break;
            case REG_IND:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(system.registers[PSW]&1)
                  system.registers[PC]=*((short*)(&system.memory_vector[(system.registers[regS])]));
              }
              break;
            case REG_IND_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(system.registers[PSW]&1)
                  system.registers[PC]=*((short*)(&system.memory_vector[system.registers[regS]+(((short)data_high)<<8|data_low)]));
              }
              break;
          }
          break;
        case JNE:
          reg_byte=system.memory_vector[system.registers[PC]++];
          addr_mode_byte=system.memory_vector[system.registers[PC]++];
          regS=reg_byte&0x0F;
          addressingType=addr_mode_byte&0x0F;
          updateType=addr_mode_byte>>4;
          
          switch(addressingType)
          {
            case IMMEDIATE:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&1))
                  system.registers[PC]=((short)data_high)<<8|data_low;
              }
              break;
            case MEMORY:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&1))
                  system.registers[PC]=*((short*)(&(system.memory_vector[((short)data_high)<<8|data_low])));
              }
              break;
            case REG_DIR:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&1))
                  system.registers[PC]=system.registers[regS];
              }
              break;
            case REG_DIR_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&1))
                  system.registers[PC]=system.registers[regS]+(((short)data_high)<<8|data_low);
              }
              break;
            case REG_IND:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&1))
                  system.registers[PC]=*((short*)(&system.memory_vector[(system.registers[regS])]));
              }
              break;
            case REG_IND_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&1))
                  system.registers[PC]=*((short*)(&system.memory_vector[system.registers[regS]+(((short)data_high)<<8|data_low)]));
              }
              break;
          }
          break;
        case JGT:
          reg_byte=system.memory_vector[system.registers[PC]++];
          addr_mode_byte=system.memory_vector[system.registers[PC]++];
          regS=reg_byte&0x0F;
          addressingType=addr_mode_byte&0x0F;
          updateType=addr_mode_byte>>4;
          
          switch(addressingType)
          {
            case IMMEDIATE:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&(1<<3)))
                  system.registers[PC]=((short)data_high)<<8|data_low;
              }
              break;
            case MEMORY:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&(1<<3)))
                  system.registers[PC]=*((short*)(&(system.memory_vector[((short)data_high)<<8|data_low])));
              }
              break;
            case REG_DIR:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&(1<<3)))
                  system.registers[PC]=system.registers[regS];
              }
              break;
            case REG_DIR_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&(1<<3)))
                  system.registers[PC]=system.registers[regS]+(((short)data_high)<<8|data_low);
              }
              break;
            case REG_IND:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&(1<<3)))
                  system.registers[PC]=*((short*)(&system.memory_vector[(system.registers[regS])]));
              }
              break;
            case REG_IND_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if(!(system.registers[PSW]&(1<<3)))
                  system.registers[PC]=*((short*)(&system.memory_vector[system.registers[regS]+(((short)data_high)<<8|data_low)]));
              }
              break;
          }
          break;
        case XCHG:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            short temp=system.registers[regD];
            system.registers[regD]=system.registers[regS];
            system.registers[regS]=temp;
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case ADD:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            system.registers[regD]+=system.registers[regS];
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case SUB:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            system.registers[regD]-=system.registers[regS];
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case MUL:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            system.registers[regD]*=system.registers[regS];
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case DIV:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            system.registers[regD]/=system.registers[regS];
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case CMP:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            int z,o,c,n;
            c=((ushort)system.registers[regS])>((ushort)system.registers[regD]);
            short oldRegD=system.registers[regD];
            system.registers[regD]-=system.registers[regS];
            z=system.registers[regD]==0;
            n=system.registers[regD]<0;
            o=((oldRegD<0 && system.registers[regS]>0 && system.registers[regD]>0) || (oldRegD>0 && system.registers[regS]<0 && system.registers[regD]<0));
            system.registers[PSW]&=0xFFF0;
            system.registers[PSW]|=z+(o<<1)+(c<<2)+(n<<3);
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case NOT:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            system.registers[regD]=~system.registers[regD];
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case AND:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            system.registers[regD]&=system.registers[regS];
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case OR:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            system.registers[regD]|=system.registers[regS];
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case XOR:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            system.registers[regD]^=system.registers[regS];
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case TEST:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            int z,n;
            system.registers[regD]&=system.registers[regS];
            //update psw
            z=system.registers[regD]==0;
            n=system.registers[regD]<0;
            system.registers[PSW]&=0xFFF6;
            system.registers[PSW]|=z+(n<<3);
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case SHL:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            int z,c,n;
            c=system.registers[regD]>>15;
            system.registers[regD]<<=system.registers[regS];
            //update psw
            z=system.registers[regD]==0;
            n=system.registers[regD]<0;
            system.registers[PSW]&=0xFFF2;
            system.registers[PSW]|=z+(c<<2)+(n<<3);
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case SHR:
          reg_byte=system.memory_vector[system.registers[PC]++];
          regD=reg_byte>>4;
          regS=reg_byte&0x0F;
          if((regS>=0 && regS<=8) && (regD>=0 && regD<=8))
          {
            int z,c,n;
            c=system.registers[regD]&1;
            system.registers[regD]>>=system.registers[regS];
            //update psw
            z=system.registers[regD]==0;
            n=system.registers[regD]<0;
            system.registers[PSW]&=0xFFF2;
            system.registers[PSW]|=z+(c<<2)+(n<<3);
          }
          else
          {
            goto INVALID_INSTRUCTION;
          }
          break;
        case LDR:
          reg_byte=system.memory_vector[system.registers[PC]++];
          addr_mode_byte=system.memory_vector[system.registers[PC]++];
          regS=reg_byte&0x0F;
          regD=reg_byte>>4;
          addressingType=addr_mode_byte&0x0F;
          updateType=addr_mode_byte>>4;
          
          switch(addressingType)
          {
            case IMMEDIATE:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                short temp=data_high;
                system.registers[regD]=(temp<<8)|((unsigned char)data_low);
              }
              break;
            case MEMORY:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                short temp=data_high;
                system.registers[regD]=*((short*)(&(system.memory_vector[(temp<<8)|((unsigned char)data_low)])));
              }
              break;
            case REG_DIR:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.registers[regD]=system.registers[regS];
              }
              break;
            case REG_DIR_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                short temp=data_high;
                system.registers[regD]=system.registers[regS]+((temp<<8)|((unsigned char)data_low));
              }
              break;
            case REG_IND:
              if(updateType!=NO_UPDATE && updateType!=POST_INCREASE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.registers[regD]=*((short*)(&(system.memory_vector[system.registers[regS]])));
                if (updateType==POST_INCREASE)
                {
                  system.registers[regS]+=2;
                }  
              }
              break;
            case REG_IND_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                short temp=data_high;
                system.registers[regD]=*((short*)(&(system.memory_vector[system.registers[regS]+((temp<<8)|((unsigned char)data_low))])));
              }
              break;
          }
          break;
        case STR:
          reg_byte=system.memory_vector[system.registers[PC]++];
          addr_mode_byte=system.memory_vector[system.registers[PC]++];
          regS=reg_byte&0x0F;
          regD=reg_byte>>4;
          addressingType=addr_mode_byte&0x0F;
          updateType=addr_mode_byte>>4;
          
          switch(addressingType)
          {
            case IMMEDIATE:
              goto INVALID_INSTRUCTION;
              break;
            case MEMORY:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                short temp=data_high;
                *((short*)(&(system.memory_vector[(temp<<8)|((unsigned char)data_low)])))=system.registers[regD];
              }
              break;
            case REG_DIR:
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                system.registers[regS]=system.registers[regD];
              }
              break;
            case REG_DIR_WITH_ADD:
              goto INVALID_INSTRUCTION;
              break;
            case REG_IND:
              if(updateType!=NO_UPDATE && updateType!=PRE_DECREASE) goto INVALID_INSTRUCTION;//greska
              else
              {
                if (updateType==PRE_DECREASE)
                {
                  system.registers[regS]-=2;
                }  
                *((short*)(&(system.memory_vector[system.registers[regS]])))=system.registers[regD];
              }
              break;
            case REG_IND_WITH_ADD:
              data_low=system.memory_vector[system.registers[PC]++];
              data_high=system.memory_vector[system.registers[PC]++];
              if(updateType!=NO_UPDATE) goto INVALID_INSTRUCTION;//greska
              else
              {
                short temp=data_high;
                *((short*)(&(system.memory_vector[system.registers[regS]+((temp<<8)|((unsigned char)data_low))])))=system.registers[regD];
              }
              break;
          }
          break;
        INVALID_INSTRUCTION:
          //INVALID OP CODE
          printf("INVALID INSTRUCTION");
          exit(1);
          break;
        default:
          goto INVALID_INSTRUCTION;
          break;
      }
    }


    return 0;
}