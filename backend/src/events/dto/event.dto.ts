import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class EventMetadataDto {
  @ApiProperty()
  title: string;

  @ApiProperty()
  description: string;

  @ApiPropertyOptional()
  walrusBlobId?: string;

  @ApiPropertyOptional()
  imageUrl?: string;

  @ApiProperty()
  category: string;

  @ApiProperty({ type: [String] })
  tags: string[];
}

export class EventConfigDto {
  @ApiProperty()
  startTime: string;

  @ApiProperty()
  endTime: string;

  @ApiProperty()
  registrationDeadline: string;

  @ApiProperty()
  capacity: number;

  @ApiProperty()
  ticketPrice: string;

  @ApiProperty()
  requiresApproval: boolean;

  @ApiProperty()
  isTransferable: boolean;

  @ApiProperty()
  refundDeadline: string;
}

export class EventStatsDto {
  @ApiProperty()
  registered: number;

  @ApiProperty()
  attended: number;

  @ApiProperty()
  revenue: string;

  @ApiProperty()
  refunded: string;
}

export class EventResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  organizer: string;

  @ApiProperty()
  metadata: EventMetadataDto;

  @ApiProperty()
  config: EventConfigDto;

  @ApiProperty()
  stats: EventStatsDto;

  @ApiProperty({ enum: ['draft', 'open', 'in_progress', 'completed', 'cancelled'] })
  status: string;

  @ApiProperty()
  createdAt: string;

  @ApiProperty()
  updatedAt: string;
}

export class EventListResponseDto {
  @ApiProperty({ type: [EventResponseDto] })
  events: EventResponseDto[];

  @ApiPropertyOptional()
  nextCursor?: string;

  @ApiProperty()
  hasMore: boolean;
}
