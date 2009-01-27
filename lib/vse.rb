class VSE  
  def initialize(username, password)
    @username, @password = username, password
    @agent = WWW::Mechanize.new
    
    @portfolios = []
    
    if login(username, password)
      @logged_in = true
    else
      @logged_in = false
    end
  end
  
  def login(username, password)
    login_page = @agent.get('http://vse.marketwatch.com/Game/Homepage.aspx')

    login_form = login_page.forms.first
    login_form['LoginCenter1$_Email']    = username
    login_form['LoginCenter1$_Password'] = password

    @home = @agent.submit(login_form, login_form.buttons.first)
    
    get_portfolios    
    return true
  end
  
  def get_portfolios
    @home.search("div.gamename").to_a.each do |game_block|
      @portfolios << {
        :name => game_block.at('p').inner_text.strip,
        :target => game_block.at('div.leftnavlistsdiv').at('a').attributes['href'].match(/javascript:__doPostBack\('(.+?)',''\)/).to_a.last.strip
      }
    end
  end
  
  def portfolios
    @portfolios.collect { |portfolio| portfolio[:name] }
  end
  
  def portfolio
    @portfolio ||= @portfolios.first
    return @portfolio 
  end
  
  def portfolio=(portfolio)
    @portfolio = @portfolios.find(Proc.new { @portfolios.first }) {|p| p[:name] == portfolio }
  end
  
  def holdings(after_hours = true, refresh = false)
    load_holdings(after_hours) if (refresh || @holdings.nil?)
    return @holdings
  end
  
  def load_holdings(after_hours)
    portfolio_page = load_portfolio_page
    
    rows = portfolio_page.at("table[@id='_HoldingsDataGrid']").search('tr').to_a
    rows.shift

    @holdings = []
    rows.to_a.each do |row|
      columns = row.search('td').to_a

      @holdings << [columns[1].search('p.textalignleft').inner_text.strip, {
        :quantity => columns[2].inner_text,
        :type => columns[3].inner_text.strip,
        :change => columns[4].inner_text,
        :value => columns[5].inner_text,
        :last => columns[6].inner_text,
        :cost => columns[7].inner_text,
        :gain => columns[8].inner_text,
        :equity => columns[9].inner_text
      }]
    end
    
    append_after_hours if !market_open? && after_hours
  end
  
  def load_portfolio_page
    page_form = @home.forms.first

    page_form['__EVENTTARGET'] = portfolio[:target]
    page_form['__EVENTARGUMENT'] = ''

    return @agent.submit(page_form)
  end
  
  def append_after_hours
    after_hours = load_after_hours
    after_hours.each do |ticker, after|
      [*@holdings.select {|t, h| t == ticker}].each do |ticker, holding|
        after_minus_last = (after.to_f - holding[:last][1..-1].to_f).round!
        after_minus_cost = (after.to_f - holding[:cost][1..-1].to_f).round!

        if after_minus_last.length == 4 && after_minus_last.to_f < 0 then after_minus_last << '0' end  
        if after_minus_cost.length == 4 && after_minus_cost.to_f < 0 then after_minus_cost << '0' end

        if after_minus_cost.to_f >= 0 then after_minus_cost = "+#{after_minus_cost}" end
        if after_minus_last.to_f >= 0 then after_minus_last = "+#{after_minus_last}" end

        after_gain = ((after.to_f - holding[:cost].delete('$').to_f) * holding[:quantity].to_f).round!

        if holding[:type] == 'S'
          after_gain = (after_gain.to_f / -1).to_s
        end

        if after_gain.to_f > 10 && after_gain.length <= 5 then after_gain << '0' end

        if after_gain.to_f < -10 && after_gain.length < 6   
          after_gain = "-$#{(after_gain.to_f / -1.0).to_s.ljust(5, '0')}"
        elsif after_gain.to_f < 0
          after_gain = "-$#{(after_gain.to_f / -1.0).to_s.ljust(5, '0')}"
        else
          after_gain = "+$#{after_gain.to_s.ljust(4, '0')}"
        end
        
        @holdings.at(@holdings.index([ticker, holding]))[1].merge!({
          :after_gain => after_gain,
          :after_minus_last => after_minus_last,
          :after_minus_cost => after_minus_cost
        })
      end
    end
  end
  
  def load_after_hours
    tickers = @holdings.collect {|holding| holding[0]}.uniq
    page = Nokogiri::HTML(open("http://www.marketwatch.com/Quotes/quotes.aspx?symb=#{tickers.join(',')}"))

    after_hours_array = {}
    rows = page.search('div#multiquote/div.table//div.afterhoursrow').to_a  

    begin
      tickers.each do |ticker|
        after_hours_array[ticker] = page.search("span[@mwsymbol='#{ticker}']").find {|span| span.attributes['mwfield'] == 'ExtendedPrice'}.inner_text
      end
    rescue
      tickers.each_with_index do |ticker, index|
        after_hours_array[ticker] = rows[index].search('div.multiquoteprice//span').to_a.last.inner_text
      end
    end
    
    return after_hours_array
  end
  
  def market_open?    
    unless !(Time.now.strftime('%a') == 'Sat' || Time.now.strftime('%a') == 'Sun') && Time.now.strftime('%H').to_i >= 9 && Time.now.strftime('%H').to_i <= 15
      return false
    else
      return true
    end
  end
  
  def logged_in?
    @logged_in
  end    
end