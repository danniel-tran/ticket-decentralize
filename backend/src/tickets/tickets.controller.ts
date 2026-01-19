import { Controller, Get, Param, Query } from '@nestjs/common';
import { ApiOperation, ApiParam, ApiQuery, ApiResponse, ApiTags } from '@nestjs/swagger';
import { TicketsService } from './tickets.service';
import { TicketResponseDto, ValidateTicketResponseDto } from './dto/ticket.dto';

@ApiTags('tickets')
@Controller('tickets')
export class TicketsController {
  constructor(private readonly ticketsService: TicketsService) {}

  @Get(':id')
  @ApiOperation({ summary: 'Get ticket by ID' })
  @ApiParam({ name: 'id', description: 'Ticket object ID' })
  @ApiResponse({ status: 200, type: TicketResponseDto })
  async getTicket(@Param('id') id: string): Promise<TicketResponseDto | null> {
    return this.ticketsService.getTicket(id);
  }

  @Get('owner/:address')
  @ApiOperation({ summary: 'Get tickets by owner address' })
  @ApiParam({ name: 'address', description: 'Owner wallet address' })
  @ApiResponse({ status: 200, type: [TicketResponseDto] })
  async getTicketsByOwner(@Param('address') address: string): Promise<TicketResponseDto[]> {
    return this.ticketsService.getTicketsByOwner(address);
  }

  @Get('event/:eventId')
  @ApiOperation({ summary: 'Get tickets for an event' })
  @ApiParam({ name: 'eventId', description: 'Event object ID' })
  @ApiResponse({ status: 200, type: [TicketResponseDto] })
  async getTicketsByEvent(@Param('eventId') eventId: string): Promise<TicketResponseDto[]> {
    return this.ticketsService.getTicketsByEvent(eventId);
  }

  @Get(':id/validate')
  @ApiOperation({ summary: 'Validate a ticket for an event' })
  @ApiParam({ name: 'id', description: 'Ticket object ID' })
  @ApiQuery({ name: 'eventId', description: 'Event object ID' })
  @ApiResponse({ status: 200, type: ValidateTicketResponseDto })
  async validateTicket(
    @Param('id') id: string,
    @Query('eventId') eventId: string,
  ): Promise<ValidateTicketResponseDto> {
    return this.ticketsService.validateTicket(id, eventId);
  }
}