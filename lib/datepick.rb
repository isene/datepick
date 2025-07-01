require 'date'
require 'json'
require 'rcurses'

class DatePicker
  include Rcurses::Input
  
  CONFIG_FILE = File.expand_path('~/.datepick')
  
  DEFAULT_CONFIG = {
    'date_format' => '%Y-%m-%d',
    'months_before' => 1,
    'months_after' => 1,
    'week_starts_monday' => true,
    'highlight_weekends' => true,
    'colors' => {
      'year' => 14,      # cyan
      'month' => 10,     # green
      'day' => 15,       # white
      'selected' => 11,  # yellow
      'today' => 13,     # magenta
      'weekend' => 9     # red
    }
  }.freeze
  
  # Common date formats for quick selection
  DATE_FORMATS = {
    '1' => '%Y-%m-%d',        # ISO format
    '2' => '%d/%m/%Y',        # European
    '3' => '%m/%d/%Y',        # US format
    '4' => '%B %d, %Y',       # Long format
    '5' => '%b %d, %Y',       # Abbreviated
    '6' => '%Y%m%d',          # Compact
    '7' => '%d-%b-%Y',        # DD-Mon-YYYY
    '8' => '%A, %B %d, %Y'    # Full with weekday
  }

  def initialize
    @config = load_config
    @selected_date = Date.today
    @current_month = Date.today
    @config_mode = false
    @config_selected = 0
    @screen_w = `tput cols`.to_i
    @screen_h = `tput lines`.to_i
    
    # Initialize panes
    @main_pane = Rcurses::Pane.new(1, 1, @screen_w, @screen_h - 4, nil, nil)
    @main_pane.border = false
    
    @help_pane = Rcurses::Pane.new(1, @screen_h - 3, @screen_w, 1, nil, nil)
    @help_pane.border = false
    
    @status_pane = Rcurses::Pane.new(1, @screen_h - 1, @screen_w, 1, nil, nil)
    @status_pane.border = false
    
    @prev_content = ""
  end

  def run
    Rcurses.init!
    Rcurses::Cursor.hide
    
    begin
      # Initial display
      render
      
      loop do
        input = handle_input
        break if input == :exit
        render
      end
    rescue Interrupt
      # Exit cleanly on Ctrl-C
    ensure
      Rcurses.cleanup!
    end
  end

  private

  def load_config
    if File.exist?(CONFIG_FILE)
      JSON.parse(File.read(CONFIG_FILE))
    else
      DEFAULT_CONFIG.dup
    end
  rescue JSON::ParserError
    DEFAULT_CONFIG.dup
  end

  def save_config
    File.write(CONFIG_FILE, JSON.pretty_generate(@config))
  end

  def render
    if @config_mode
      render_config
    else
      render_calendar
    end
    
    # Update help text
    help_text = if @config_mode
      "Navigate: ↑↓ | Edit: Enter | Cancel: Esc".fg(245)
    else
      help_parts = []
      help_parts << "←↓↑→/hjkl" if @numeric_prefix.nil? || @numeric_prefix.empty?
      help_parts << "#{@numeric_prefix}g:jump #{@numeric_prefix} days" if @numeric_prefix && !@numeric_prefix.empty?
      help_parts << "n/p:month | N/P:year | t:today | H/L:week | Home/End:month | Enter:select | c:config | q:quit"
      help_parts.join(" | ").fg(245)
    end
    
    @help_pane.text = help_text
    @help_pane.refresh
    
    # Update status
    status_text = "Selected: #{@selected_date.strftime(@config['date_format'])}".fg(@config['colors']['selected'])
    @status_pane.text = status_text
    @status_pane.refresh
  end

  def render_calendar
    content = generate_calendar_content
    
    # Only update if content changed
    if content != @prev_content
      @main_pane.text = content
      @main_pane.refresh
      @prev_content = content
    end
  end

  def generate_calendar_content
    lines = []
    months_to_display = []
    
    # Calculate range of months to display
    start_month = @current_month.prev_month(@config['months_before'])
    end_month = @current_month.next_month(@config['months_after'])
    
    current = start_month
    while current <= end_month
      months_to_display << current
      current = current.next_month
    end
    
    # Generate months horizontally
    months_per_row = [(@screen_w - 4) / 22, 1].max
    
    months_to_display.each_slice(months_per_row) do |month_group|
      # Generate this row of months
      month_lines = generate_month_row(month_group)
      lines.concat(month_lines)
      lines << "" # Add spacing between month rows
    end
    
    lines.join("\n")
  end

  def generate_month_row(months)
    result_lines = []
    max_weeks = 6
    
    # Header line with month names
    header_line = ""
    months.each_with_index do |month_date, idx|
      month_str = month_date.strftime("%B %Y")
      # Highlight current month with bold and underline
      if month_date.year == Date.today.year && month_date.month == Date.today.month
        month_str = month_str.fg(@config['colors']['month']).b.u
      else
        month_str = month_str.fg(@config['colors']['month'])
      end
      header_line += month_str.ljust(22 + month_str.length - month_date.strftime("%B %Y").length)
    end
    result_lines << header_line
    
    # Day headers
    day_header_line = ""
    months.each do |month_date|
      days = @config['week_starts_monday'] ? %w[Mo Tu We Th Fr Sa Su] : %w[Su Mo Tu We Th Fr Sa]
      days.each_with_index do |day, idx|
        # Use darker colors for day headers and make them bold
        color = ((@config['week_starts_monday'] && idx >= 5) || (!@config['week_starts_monday'] && (idx == 0 || idx == 6))) ? 
                88 : 244  # Dark red for weekends, dark gray for weekdays
        day_header_line += day.fg(color).b + " "
      end
      day_header_line += " " # Extra space between months
    end
    result_lines << day_header_line
    
    # Generate week lines
    week_data = months.map { |m| generate_month_weeks(m) }
    
    (0...max_weeks).each do |week_idx|
      week_line = ""
      months.each_with_index do |month_date, month_idx|
        week = week_data[month_idx][week_idx] || []
        
        7.times do |day_idx|
          if week[day_idx]
            date = week[day_idx]
            day_str = date.day.to_s.rjust(2)
            
            # Apply styling
            if date == @selected_date
              day_str = day_str.fb(@config['colors']['selected'], 236).b
            elsif date == Date.today
              day_str = day_str.fg(@config['colors']['today']).b
            elsif date.saturday? || date.sunday?
              day_str = day_str.fg(@config['colors']['weekend'])
            else
              day_str = day_str.fg(@config['colors']['day'])
            end
            
            week_line += day_str + " "
          else
            week_line += "   "
          end
        end
        week_line += " " # Extra space between months
      end
      result_lines << week_line unless week_line.strip.empty?
    end
    
    result_lines
  end

  def generate_month_weeks(month_date)
    weeks = []
    current_week = []
    
    first_day = Date.new(month_date.year, month_date.month, 1)
    last_day = Date.new(month_date.year, month_date.month, -1)
    
    # Calculate starting position
    wday = first_day.wday
    if @config['week_starts_monday']
      wday = (wday - 1) % 7
    end
    
    # Add empty days at the beginning
    wday.times { current_week << nil }
    
    # Add all days of the month
    (first_day..last_day).each do |date|
      current_week << date
      
      # Check if week is complete
      if @config['week_starts_monday']
        if date.wday == 0 # Sunday
          weeks << current_week
          current_week = []
        end
      else
        if date.wday == 6 # Saturday
          weeks << current_week
          current_week = []
        end
      end
    end
    
    # Add the last week if it has any days
    weeks << current_week unless current_week.empty?
    
    weeks
  end

  def render_config
    config_items = [
      ["Date format", @config['date_format']],
      ["Months before", @config['months_before'].to_s],
      ["Months after", @config['months_after'].to_s],
      ["Week starts Monday", @config['week_starts_monday'] ? "Yes" : "No"],
      ["Save and exit config", "Press Enter"]
    ]
    
    lines = []
    lines << ""
    lines << "Configuration".fg(@config['colors']['year']).b
    lines << ""
    
    config_items.each_with_index do |(label, value), idx|
      line = "  #{label}: #{value}"
      if idx == @config_selected
        line = line.fb(0, 15)
      end
      lines << line
      lines << "" # Add spacing
    end
    
    content = lines.join("\n")
    
    # Always refresh config screen to show updated values
    @main_pane.text = content
    @main_pane.refresh
    @prev_content = content
  end

  def handle_input
    ch = getchr
    
    if @config_mode
      handle_config_input(ch)
    else
      handle_calendar_input(ch)
    end
  end

  def handle_calendar_input(ch)
    # Reset numeric prefix for non-numeric keys (except 'g')
    if ch !~ /[0-9g]/ && @numeric_prefix
      @numeric_prefix = ""
    end
    
    case ch
    when 'q', 'Q'
      return :exit
    when 'c', 'C'
      @config_mode = true
      @config_selected = 0
      @prev_content = "" # Force refresh
    when 'ENTER'
      Rcurses.cleanup!
      puts @selected_date.strftime(@config['date_format'])
      exit
    when 'LEFT', 'h', 'H'
      @selected_date = @selected_date.prev_day
      update_current_month
    when 'RIGHT', 'l', 'L'
      @selected_date = @selected_date.next_day
      update_current_month
    when 'UP', 'k', 'K'
      @selected_date = @selected_date.prev_day(7)
      update_current_month
    when 'DOWN', 'j', 'J'
      @selected_date = @selected_date.next_day(7)
      update_current_month
    when 'w', 'W'
      @selected_date = @selected_date.next_day(7)
      update_current_month
    when 'b', 'B'
      @selected_date = @selected_date.prev_day(7)
      update_current_month
    when 'n'
      @selected_date = @selected_date.next_month
      update_current_month
    when 'p'
      @selected_date = @selected_date.prev_month
      update_current_month
    when 'N'
      @selected_date = @selected_date.next_year
      update_current_month
    when 'P'
      @selected_date = @selected_date.prev_year
      update_current_month
    when 'H', '^'
      # Go to start of week
      days_back = @config['week_starts_monday'] ? 
                  (@selected_date.wday == 0 ? 6 : @selected_date.wday - 1) :
                  @selected_date.wday
      @selected_date = @selected_date.prev_day(days_back)
      update_current_month
    when 'L', '$'
      # Go to end of week
      days_forward = @config['week_starts_monday'] ?
                     (7 - (@selected_date.wday == 0 ? 7 : @selected_date.wday)) :
                     (6 - @selected_date.wday)
      @selected_date = @selected_date.next_day(days_forward)
      update_current_month
    when 'HOME'
      # Go to start of month
      @selected_date = Date.new(@selected_date.year, @selected_date.month, 1)
      update_current_month
    when 'END'
      # Go to end of month
      @selected_date = Date.new(@selected_date.year, @selected_date.month, -1)
      update_current_month
    when 't', 'T'
      # Go to today
      @selected_date = Date.today
      @current_month = Date.today
    when '0'..'9'
      # Numeric prefix for jumps (vim-style)
      @numeric_prefix ||= ""
      @numeric_prefix += ch
    when 'g'
      # Execute numeric jump
      if @numeric_prefix && !@numeric_prefix.empty?
        days = @numeric_prefix.to_i
        @selected_date = @selected_date.next_day(days)
        update_current_month
        @numeric_prefix = ""
      end
    when 'r', 'R'
      # Force full refresh
      Rcurses.clear_screen
      @prev_content = ""
      @main_pane.full_refresh
      @help_pane.full_refresh
      @status_pane.full_refresh
    end
  end

  def handle_config_input(ch)
    case ch
    when 'ESC', 'q', 'Q'
      @config_mode = false
      @prev_content = "" # Force refresh
    when 'UP', 'k', 'K'
      @config_selected = (@config_selected - 1) % 5
    when 'DOWN', 'j', 'J'
      @config_selected = (@config_selected + 1) % 5
    when 'ENTER'
      handle_config_edit
      render_config  # Immediately re-render config after edit
    end
  end

  def handle_config_edit
    case @config_selected
    when 0 # Date format
      format_help = DATE_FORMATS.map { |k, v| "#{k}: #{Date.today.strftime(v)}" }.join(" | ")
      new_format = get_input_with_help("Date format", @config['date_format'], format_help)
      # Check if user entered a number for quick format selection
      if new_format && DATE_FORMATS[new_format]
        @config['date_format'] = DATE_FORMATS[new_format]
      elsif new_format && !new_format.empty?
        @config['date_format'] = new_format
      end
      @prev_content = ""  # Force refresh to show new value
    when 1 # Months before
      old_value = @config['months_before']
      new_value = get_input("Months before", old_value.to_s)
      if new_value && new_value != old_value.to_s
        @config['months_before'] = new_value.to_i
      end
      @prev_content = ""  # Force refresh to show new value
    when 2 # Months after
      new_value = get_input("Months after", @config['months_after'].to_s)
      if new_value && new_value.to_i > 0
        @config['months_after'] = new_value.to_i
      end
      @prev_content = ""  # Force refresh to show new value
    when 3 # Week starts Monday
      @config['week_starts_monday'] = !@config['week_starts_monday']
      @prev_content = "" # Force refresh
    when 4 # Save and exit
      save_config
      @config_mode = false
      @prev_content = "" # Force refresh
    end
  end

  def get_input(prompt, default)
    # Create input pane
    pane = Rcurses::Pane.new(2, @screen_h - 4, @screen_w - 4, 3, 15, 0)
    pane.border = true
    
    # Use ask method which properly handles input
    result = pane.ask("#{prompt}: ", default)
    
    # Force a full screen refresh after input dialog
    Rcurses.clear_screen
    @main_pane.full_refresh
    @help_pane.full_refresh
    @status_pane.full_refresh
    @prev_content = "" # Force refresh on next render
    
    # Return the result (ask already returns the text)
    result.strip
  end
  
  def get_input_with_help(prompt, default, help_text)
    # Create input pane with extra height for help
    pane = Rcurses::Pane.new(2, @screen_h - 6, @screen_w - 4, 5, 15, 0)
    pane.border = true
    
    # Show help text above input
    Rcurses::Cursor.set(@screen_h - 6, 4)
    print help_text.fg(245)
    
    # Use ask method which properly handles input
    result = pane.ask("#{prompt}: ", default)
    
    # Force a full screen refresh after input dialog
    Rcurses.clear_screen
    @main_pane.full_refresh
    @help_pane.full_refresh
    @status_pane.full_refresh
    @prev_content = "" # Force refresh on next render
    
    # Return the result (ask already returns the text)
    result.strip
  end

  def update_current_month
    @current_month = Date.new(@selected_date.year, @selected_date.month, 1)
  end
end