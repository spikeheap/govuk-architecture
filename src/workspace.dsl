workspace "GOV.UK" "The GOV.UK programme within GDS" {

  // Use hierarchical identifiers to allow shorter names within containers (e.g. "mysql").
  // The alternative (by removing the following line) is flat, so all identifiers must be unique (e.g. "publisher_signon_mysql"
  !identifiers hierarchical

  model {
    // Dependencies outside GOV.UK
    splunk = softwareSystem "Splunk" "Log aggregator for Cyber/Security groups"


    enterprise GOVUK {

      group "Publishing" {

        publishing_platform = softwareSystem "Publishing Platform" {
          search = container "Search " {
            tags QueryOwnedByPublishing
            search_api = component "Search API" "TODO!"
          }

          // TODO Signon calls out to Gds:API organisations. Which app is this?
          signon = container "Signon" "Single sign-on service for GOV.UK" {
            url https://github.com/alphagov/signon
            tags QueryOwnedByPublishing

            mysql = component "MySQL DB" "Persists user data" "MySQL" Database
            redis = component "Redis" "Store for sidekiq jobs" "Redis" Database

            component "Signon app" "Single sign-on service for GOV.UK" "Rails" {
              -> redis
              -> mysql
              -> splunk "Sends log events"
            }
          }

          account_api = container "Account API" {
            // TODO this is referenced in https://github.com/alphagov/email-alert-api/blob/92021c3e26277545f2fb99336695aed56ab781a4/app/controllers/subscribers_govuk_account_controller.rb
            // Is it different to Signon?
          }

          router_container = container "Router" "Maps paths to content on GOV.UK to publishing apps" {
            tags QueryOwnedByPublishing QueryArchitecturalSmell

            database = component "MongoDB" "Fast store for routes" "MongoDB" Database

            // TODO: what is a "backend"? It includes email-campaign-frontend, multipage-frontend, search-api
            router_api = component "Router API" "API for updating the routes used by the router on GOV.UK" {
              -> database "Create, read, update and delete routes"
            }

            router = component "Router" "Router in front on GOV.UK to proxy to backend servers on the single domain" {
              -> database "Read routes and backends into in-memory store"
            }
          }

          link_checker_api = container "Link Checker API" "Determines whether a batch of URIs are things that should be linked to" "Rails" {
            url https://github.com/alphagov/link-checker-api
            tags QueryOwnedByPublishing
          }

          asset_manager = container "Asset Manager" "Manages uploaded assets (images, PDFs etc.) for applications on GOV.UK" "Rails" {
            url https://github.com/alphagov/asset-manager
            tags QueryOwnedByPublishing
          }

          maslow = container "Maslow" "Create and manage user needs" "Rails" {
            url https://github.com/alphagov/maslow
            tags QueryOwnedByPublishing, QueryCandidateForDeprecation
          }

          content_store_container = container "Content Store" "TODO" {
            url https://github.com/alphagov/content-store
            tags QueryOwnedByPublishing

            database = component "MongoDB" "Store for content" "MongoDB" Database
            content_store = component "Content Store" "" "Rails" {
              -> database "Stores and retrieves content"
              -> router_container.router_api "Add and delete routes and rendering apps"
              -> router_container.router_api "Look up routes to idenfity inconsistent redirects"
            }
          }

          publishing_api_container = container "Publishing API" "TODO" {
            url https://github.com/alphagov/publishing-api

            database = component "PostgreSQL DB" "Persists user data" "Postgres" Database
            redis = component "Redis" "Store for sidekiq jobs" "Redis" Database
            s3 = component "S3" "Store for images, videos & file attachments" "AWS S3" 

            event_queue = component "Queue" "Queue to publish publishing events" "RabbitMQ" Queue

            publishing_api = component "Publishing API" "" "Rails" {
              -> database
              -> redis
              -> s3

              -> content_store_container.content_store "Pushes published content to the draft store"
              -> content_store_container.content_store "Pushes published content to the published store"
              -> content_store_container.content_store "Validates presence of draft content"
              -> content_store_container.content_store "Validates presence of published content"

              -> router_container.router_api "Validates presence of routes"
              -> event_queue "Broadcasts publishing events"
            }
          }

          email_alert_service = container "Email Alert Service" "Sends email alerts to the public for GOV.UK"{
            tags QueryOwnedByPublishing

            database = component "PostgreSQL DB" "Stores subscribers, subscriptions, and messages" "Postgres" Database
            redis = component "Sidekiq store" "Store for sidekiq jobs" "Redis" Database
            sent_message_store = component "Sent message store" "Stores sent messages" "Redis" Database

            email_alert_api = component "Email alert API" "Sends email alerts to the public for GOV.UK" "Rails" {
              -> database
              -> redis

              -> account_api "Get email of logged-in user"
            }

            email_alert_frontend = component "Email alert frontend" "Serves email alert signup pages on GOV.UK" "Rails" {
              -> publishing_api_container.publishing_api
              -> email_alert_api "Manage subscriptions"
              -> content_store_container.content_store "Get content items"
            }

            email_alert_service_consumer = component "Email alert service" "Message queue consumer that triggers email alerts for GOV.UK" "Rails" {
              -> publishing_api_container.event_queue "Listens for major change events"
              -> sent_message_store "Records sent messages"
              -> email_alert_api "Triggers an email alert"
            }

            email_alert_monitoring = component "Email alert monitoring" "Script run by Jenkins that verifies GOV.UK email alerts have been sent" "Ruby" {
              // TODO
            }
          }

          hmrc_manuals_api = container "HMRC Manuals API" "A thin proxy for HMRC manual publication" "Rails" {
            url https://github.com/alphagov/hmrc-manuals-api
            tags QueryCandidateForDeprecation
            -> publishing_api_container.publishing_api "Pushes published content to the content store"
          }
        

          group "Publishing apps" {
            whitehall_container = container "Whitehall" "The Whitehall publishing application" {
              url https://github.com/alphagov/whitehall
              
              mysql = component "MySQL DB" "" "MySQL" Database
              redis = component "Redis" "Taxonomy cache" "Redis" Database
              s3 = component "S3" "Store for images, videos & file attachments" "AWS S3" 

              whitehall = component "Whitehall app" "" "Rails" {
                -> mysql
                -> redis
                -> s3

                -> asset_manager "Uploads and removes assets attached to documents"
                -> content_store_container.content_store "Upload content to the content store (TODO: not all content?)"
                -> email_alert_service.email_alert_api "Email notifications for 'World location' updates"
                -> link_checker_api "Create & get batches"
                -> maslow "Get needs"
                -> publishing_api_container.publishing_api "Create & update content"
                -> router_container.router_api "Adds and removes routes"
                -> search.search_api "TODO rummages"
              }
            }

            publisher = container "Mainstream" "The Mainstream content publishing app" "Rails" {
              url https://github.com/alphagov/publisher
              -> publishing_api_container.publishing_api "Create & update content"
              -> link_checker_api "Create & get batches"
              -> maslow "Retrieve needs (? TODO validate)"
            }

            content_publisher = container "Content Publisher" "The newest content publishing app" "Rails" {
              url https://github.com/alphagov/content-publisher


              database = component "PostgreSQL DB" "Persists user data" "Postgres" Database
              redis = component "Redis" "Store for sidekiq jobs" "Redis" Database
              s3 = component "S3" "Store for images, videos & file attachments" "AWS S3" 

              content_publisher_app = component "Content Publisher app" "" "Rails" {
                -> database
                -> redis
                -> s3

                -> publishing_api_container.publishing_api "Uploads to preview and publish content"
              }
            }

            manuals_publisher = container "Manuals Publisher" "Publish manual pages on GOV.UK" "Rails" {
              url https://github.com/alphagov/manuals-publisher
              -> publishing_api_container.publishing_api "Create & update content"
              -> link_checker_api "Create & get batches"
            }

            service_manual_publisher = container "Service Manual Publisher" "Publishes the GDS Service Manual" "Rails" {
              url https://github.com/alphagov/service-manual-publisher
              -> publishing_api_container.publishing_api "Create & update content"
            }

            travel_advice_publisher = container "Travel Advice Publisher" "Publishes travel advice pages to GOV.UK" "Rails" {
              url https://github.com/alphagov/travel-advice-publisher
              -> publishing_api_container.publishing_api "Create & update content"
              -> link_checker_api "Create & get batches"
              -> maslow "Retrieve needs (? TODO validate, maybe already removed)"
            }

            collections_publisher = container "Collections Publisher" "Publishes step by steps, /browse pages, and legacy /topic pages on GOV.UK" "Rails" {
              url https://github.com/alphagov/collections-publisher
              -> publishing_api_container.publishing_api "Create & update content"
              -> link_checker_api "Create & get batches"
            }
          }
        }
      }

      group "Content Design" {
        content_designer = person "A GOV.UK Content Design team member" {
          -> publishing_platform.publisher "Creates and manages mainstream content"
          -> publishing_platform.content_publisher.content_publisher_app "Creates and manages TODO content"
          -> publishing_platform.collections_publisher "Creates and manages mainstream content"
          -> publishing_platform.travel_advice_publisher "Creates and manages mainstream content"
          -> publishing_platform.service_manual_publisher "Creates and manages mainstream content"
          -> publishing_platform.manuals_publisher "Creates and manages mainstream content"
          -> publishing_platform.whitehall_container.whitehall "Creates and manages mainstream content"
        }
      }

      group "Public Experience" {
        
      }
    }

    // Things outside GOV.UK but inside GDS
    // See also "dependenies outside GDS at the top"

    // Things outside GDS

    external_content_designer = person "Content author (non-GDS)" {
      -> publishing_platform.whitehall_container.whitehall "Creates and manages content"
      -> publishing_platform.content_publisher.content_publisher_app "Creates and manages TODO content"
    }

    external_hmrc_cms = softwareSystem "HMRC internal content management system" {
      -> publishing_platform.hmrc_manuals_api "Creates and updates manual sections" "REST"
    }

    external_hmrc_manual_editor = person "HMRC Manual editor" {
      -> external_hmrc_cms "Creates and manages HMRC manuals"
    }
  }

  !include views.dsl
    
}