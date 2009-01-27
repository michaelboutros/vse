class Float
  def round!(decimals = 2)
    ((self * 10**2).round.to_f / 10**2).to_s.ljust(4, "0")
  end
end