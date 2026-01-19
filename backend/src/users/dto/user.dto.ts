import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class UserStatsDto {
  @ApiProperty()
  eventsCreated: number;

  @ApiProperty()
  eventsAttended: number;

  @ApiProperty()
  ticketsPurchased: number;

  @ApiProperty()
  totalSpent: string;
}

export class ReputationDto {
  @ApiProperty()
  score: number;

  @ApiProperty()
  eventsHosted: number;

  @ApiProperty()
  attendanceRate: number;

  @ApiProperty()
  cancellations: number;
}

export class UserProfileResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  owner: string;

  @ApiPropertyOptional()
  username?: string;

  @ApiPropertyOptional()
  displayName?: string;

  @ApiPropertyOptional()
  bio?: string;

  @ApiPropertyOptional()
  avatarUrl?: string;

  @ApiProperty()
  stats: UserStatsDto;

  @ApiProperty()
  reputation: ReputationDto;

  @ApiProperty()
  createdAt: string;

  @ApiProperty()
  updatedAt: string;
}

export class BadgeDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  name: string;

  @ApiProperty()
  description: string;

  @ApiProperty()
  imageUrl: string;

  @ApiProperty()
  awardedAt: string;
}

export class UserBadgesResponseDto {
  @ApiProperty({ type: [BadgeDto] })
  badges: BadgeDto[];

  @ApiProperty()
  total: number;
}