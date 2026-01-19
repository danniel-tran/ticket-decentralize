import { Controller, Get, Param, Query } from '@nestjs/common';
import { ApiOperation, ApiParam, ApiQuery, ApiResponse, ApiTags } from '@nestjs/swagger';
import { EventsService } from './events.service';
import { EventResponseDto } from './dto/event.dto';

@ApiTags('events')
@Controller('events')
export class EventsController {
  constructor(private readonly eventsService: EventsService) {}

  @Get()
  @ApiOperation({ summary: 'Get recent events' })
  @ApiQuery({ name: 'limit', required: false, type: Number })
  @ApiResponse({ status: 200, type: [EventResponseDto] })
  async getRecentEvents(@Query('limit') limit?: number): Promise<EventResponseDto[]> {
    return this.eventsService.getRecentEvents(limit || 20);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get event by ID' })
  @ApiParam({ name: 'id', description: 'Event object ID' })
  @ApiResponse({ status: 200, type: EventResponseDto })
  async getEvent(@Param('id') id: string): Promise<EventResponseDto | null> {
    return this.eventsService.getEvent(id);
  }

  @Get('organizer/:address')
  @ApiOperation({ summary: 'Get events by organizer address' })
  @ApiParam({ name: 'address', description: 'Organizer wallet address' })
  @ApiResponse({ status: 200, type: [EventResponseDto] })
  async getEventsByOrganizer(@Param('address') address: string): Promise<EventResponseDto[]> {
    return this.eventsService.getEventsByOrganizer(address);
  }
}
