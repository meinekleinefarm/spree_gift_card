Spree::OrderMailer.class_eval do
  def gift_card_email(card, order)
    @gift_card = card
    @order = order
    subject = "#{Spree::Config[:site_name]} #{t('order_mailer.gift_card_email.subject')}"
    @gift_card.update_attribute(:sent_at, Time.now)
    attachments['Gutschwein.pdf'] = File.read(@gift_card.attachment)
    mail(:to => order.email, :from => from_address, :subject => subject)
  end
end
