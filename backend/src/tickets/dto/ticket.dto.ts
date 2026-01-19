import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class TicketResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  eventId: string;

  @ApiProperty()
  owner: string;

  @ApiProperty()
  originalOwner: string;

  @ApiProperty()
  ticketNumber: number;

  @ApiProperty()
  purchasePrice: string;

  @ApiProperty()
  purchasedAt: string;

  @ApiProperty()
  isUsed: boolean;

  @ApiPropertyOptional()
  usedAt?: string;

  @ApiPropertyOptional()
  encryptedData?: string;
}

export class TicketListResponseDto {
  @ApiProperty({ type: [TicketResponseDto] })
  tickets: TicketResponseDto[];

  @ApiProperty()
  total: number;
}

export class ValidateTicketResponseDto {
  @ApiProperty()
  isValid: boolean;

  @ApiProperty()
  ticketId: string;

  @ApiProperty()
  eventId: string;

  @ApiPropertyOptional()
  message?: string;
}