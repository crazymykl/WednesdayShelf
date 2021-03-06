require 'nokogiri'

class Digester < Scraper
  def is_comic_filter(listing)
    return false if listing.publisher == ""
    return false if listing.price.gsub("$", "").to_f > 7.00
    return false if listing.full_title.include? " TP"
    return false if listing.full_title.include? " HC"
    return true
  end

  def digest_into_create_hash(listing)
    create_hash = {}
    #basic strings
    create_hash[:title] = listing.full_title
    create_hash[:description] = listing.full_desc
    create_hash[:diamond_no] = listing.diamd_no
    create_hash[:stock_no] = listing.stock_no
    create_hash[:writer] = listing.writer
    create_hash[:artist] = listing.artist
    create_hash[:cover_artist] = listing.cover_artist
    #integers
    create_hash[:issue_no] = listing.issue_no.to_i
    create_hash[:max_issue] = listing.max_issue.to_i
    #float
    create_hash[:price] = listing.price.gsub("S", "").to_f
    return create_hash
  end

  def digest(p)
    @name = "Alex Mother Loving Jarvis"
    p.listings.each do |listing|
      is_comic = is_comic_filter(listing)
      next if is_comic == false
      ship_date = DateTime.strptime(listing.ship_date, "%m/%d/%Y")

      @release = Release.where(:ship_date => ship_date).first_or_create
      create_hash = digest_into_create_hash listing
      if listing.full_title.include? @name
        var = Variant.where(create_hash).first_or_create
        var.issue = Issue.where(:title => @name)[0]
        var.save
        puts "-=+=- -=+=- -=+=- "
        puts "VARIANT RECORDED for #{var.issue.title} => #{var.title}"
        puts "-=+=- -=+=- -=+=- "
        next
      end
      if listing.full_title.match(/^(.+)#\d+/)
        @name = listing.full_title.match(/^(.+)#\d+/).to_s
      else
        @name = listing.full_title
      end
      create_hash.merge!(:title => @name)
      @issue = Issue.where(create_hash).first_or_create
      puts "-=+=- -=+=- -=+=- "
      puts "ISSUE RECORDED - #{@issue.title}"
      puts "-=+=- -=+=- -=+=- "
      @release.issues << @issue
      next if listing.main_desc == nil
      @series = Series.where(:name => listing.main_desc ).first_or_create
      @series.issues << @issue
      @publisher = Publisher.where(:name => listing.publisher).first_or_create
      @publisher.series << @series
    end
  p.digested = true
  p.save
  return nil
  end

  def update_shipping
    login
    Release.all_future.each do |release|
      release.issues.each do |issue|
        code = issue.diamond_no
        url = "#{ENV['BASE_URL']}#{ENV['FANCBOX_URL']}#{code}".gsub("\n", "")  #NOTE Ugly Gsub fix.
        puts url
        html = @agent.get(url).body
        doc = Nokogiri::HTML(html)
      if doc.search("[text()*='could not be found or is currently not in stock.']").empty? == false
        issue.variants.destroy_all
        issue.destroy
        puts "GONE"
        next
      end
      if doc.search("[text()*='CANCELLED']").empty?  == false
        issue.variants.destroy_all
        issue.destroy
        puts "CANCELLED"
        next
      end
        raw_ship = doc.search("[text()*='Est Ship Date']")[0].parent.parent.css('.LookupItemData_Value').text.strip
        ship_date = DateTime.strptime(raw_ship, "%m/%d/%Y")
        issue.release = Release.where(:ship_date => ship_date).first_or_create
        issue.save
      end
    end
  end


  def get_imgurl(stock)
    stock_no = stock.gsub("STK", "")
    head_num = stock_no[0]
    key_num = stock_no[1].to_i
    trailing_num = stock_no[2..30]
    if trailing_num.to_i == 0
      if key_num.odd?
        url = "#{ENV['BASE_URL']}/Image/Display?pd=webdata/catalogimages/STK_IMAGES/STK#{head_num}#{key_num - 1}0001-#{head_num}#{key_num + 1}0000&pf=#{stock}.jpg"
      else
        url = "#{ENV['BASE_URL']}/Image/Display?pd=webdata/catalogimages/STK_IMAGES/STK#{head_num}#{key_num - 2}0001-#{head_num}#{key_num}0000&pf=#{stock}.jpg"

      end
    else
      if key_num.odd?
        url = "#{ENV['BASE_URL']}/Image/Display?pd=webdata/catalogimages/STK_IMAGES/STK#{head_num}#{key_num - 1}0001-#{head_num}#{key_num + 1}0000&pf=#{stock}.jpg"
      else
        url = "#{ENV['BASE_URL']}/Image/Display?pd=webdata/catalogimages/STK_IMAGES/STK#{head_num}#{key_num}0001-#{head_num}#{key_num + 2}0000&pf=#{stock}.jpg"
      end
    end
  end

  def download_image(issue, agent)
    imgurl = get_imgurl(issue.stock_no)
    file = MechanizeClip.get(imgurl, agent)
    issue.cover = file
    issue.save
    puts "Cover for #{issue.title} Downloaded!"
    puts issue.cover.url
  end

  def download_all_covers
    puts "================"
    puts "DOWNLOADING COVERS"
    puts "================"
    login
    Issue.where(:has_cover => false).each do |issue|
      download_image(issue, @agent)
      issue.has_cover = true
      issue.save
    end
    Variant.where(:has_cover => false).each do |issue|
      download_image(issue, @agent)
      issue.has_cover = true
      issue.save
    end
  end
end
