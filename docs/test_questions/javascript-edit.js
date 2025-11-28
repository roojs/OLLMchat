this is code from a google sheets script (i dont have direct access on the machines, so you will have to guess what the bits that are not included are about.

    basically i truns, however when it trys to do an 'add' we already do a try catch which catches the error code 6140 - which indicates it's already been added. we then proceed to fetch the new order and try and update it.
    
    rather than keep adding i want to use  PropertiesService.getScriptProperties(); so we dont keep trying to add it, we detect that it's aready added by checking those values and do an update instead
    
    
    I need small chunks with context on what to replace - avoid creating temporary variable that are just used once test on existing values if the exist
    
    write this code to /tmp/test.gs
    and the updated version to /tmp/test-changed.gs
    
    
    
    
    function syncPayments(assign_valid, job_valid)
    {
        Logger.log("syncPayments");
        if (typeof(assign_valid) == 'undefined') {
          throw "Run from sync all";
        }
      
        syncPayments.init(assign_valid, job_valid);
        syncPayments.buildPayments(assign_valid);
    
    
    
        Logger.log("Payment List: %d", syncPayments.paym.length);
    
        var done  = 0;
        syncPayments.paym.forEach(function(p) {
    
           //if (done > 300) { return; } // for debug
    
          if (p.assigns.leading < 1) {
            Logger.log("Skip No asssignments for %s", p.Id);
            return;
          }
          
    
          if (p.qb !== false && p.qb.qb_last_sent > p.last_modified) {
            //Logger.log("Skip Already updtodate %s %s > %s", p.Id, p.qb === false ? 'x' : p.qb.qb_last_sent, p.last_modified);
            Logger.log(" (%d/%d) Skip Already updtodate %s %s  > %s", syncPayments.paym.indexOf(p), syncPayments.paym.length,  p.Id, p.qb.qb_last_sent , p.last_modified );
            return;
          }
          if (p.qb !== false && p.qb.qb_status.match(/^RENAMED/)) {
    
            Logger.log("Skip RENAMED %s (%d/%d)", p.Id, syncPayments.paym.indexOf(p), syncPayments.paym.length);
            return;
          }
          //Logger.log("Date Check %s %s > %s", p.Id, p.qb === false ? 'x' : p.qb.qb_last_sent, p.last_modified);
    
    
          var jdata = mapPaymentToBill(p);
          if (jdata === false) {
            Logger.log("mapPaymentToBill returned false (empty payment probably / or not approved)");
            return;
          }
    
          
    
    
          if (jdata.DocNumber.length > 22) {
            throw "ERROR : document number too long %s - add a map in mapPaymentToBill", jdata.DocNumber;
            return;
          }
          Logger.log("Update    %s",  jdata.DocNumber);
          var upd = false;
          var old = false;
          try {
    
            if (typeof(jdata.Id) != 'undefined') {
              old = quickbooksGet("PurchaseOrder", jdata.Id);
               if (old === false) {
                Logger.log("SKIP - %s has been deleted ", jdata.DocNumber);
                 p.qb_updated  = p.last_modified;
                 p.qb_status = "DELETED";
                return;
              }
              Logger.log(old);
              if (!jdata.DocNumber.match(/\-23\-05\-31$/) &&     old["PurchaseOrder"].DocNumber != jdata.DocNumber)  {
                Logger.log("SKIP - %s - it has been renamed to  %s", jdata.DocNumber,  old["PurchaseOrder"] ? old["PurchaseOrder"].DocNumber : "Unknonwn?" );
                Logger.log(old);
                 p.qb_updated  = p.last_modified;
                 p.qb_status = "RENAMED TO " + old["PurchaseOrder"].DocNumber;
                return;
              }
              if (syncAll.is_dry_run) {
                  syncPayments.proposedUpdate(jdata);  
                  return;
              }
              upd = quickbooksUpdate("PurchaseOrder", jdata, old);
            } else {
              if (syncAll.is_dry_run) {
                  syncPayments.proposedAdd(jdata);  
                  return;
              }
              upd = quickbooksUpdate("PurchaseOrder", jdata, old);
               
               
            }
    
            
          } catch (e) {
            
            Logger.log(e);
            Logger.log(e.stack);
            if (e.error !== false && e.error.code == 6140 && p.qb == false) {
                // we dont have the id for it.. we should probably look for it.
                var look = quickbooksQuery("SELECT * FROM PurchaseOrder where DocNumber = '" + jdata.DocNumber + "'");
                if (look.QueryResponse.PurchaseOrder.length != 1) {
                  Logger.log(JSON.stringify(look, null, 2));
                  throw "Cant find duplicate invoice";
                }
                jdata.Id = look.QueryResponse.PurchaseOrder[0].Id;
                upd = quickbooksUpdate("PurchaseOrder", jdata);
    
    
    
                
                //Logger.log(JSON.stringify(look, null, 2));
                //throw "OOPS";
             } else if  (e.error !== false && e.error.code == 610 ) {
              Logger.log("Trying to edit a deleted transaction - skip");
               p.qb_updated  = p.last_modified;
              return;
             } else if 
             ( ["LE115281218-25-07-31" , "LE115281218-25-10-31"].indexOf(jdata.DocNumber) > -1) {
                return; // skip invalid
    
            } else {
              Logger.log(JSON.stringify(jdata,null,2));
              throw "Got unexpected result from  update purchase order";
            }
          }
    
          if (upd === false) {
            Logger.log("quickbook update returned false (PurchaseOrder) voided or paid)");
            return;
          }
          //throw "Done an update";
          
          if (p.qb == false) {
            Logger.log(upd);
            p.qb_new_id = upd.PurchaseOrder.Id
          }
          p.qb_updated  = p.last_modified;
          done++;
    
        });
    
        if (syncAll.is_dry_run) {
          return;
        }
        // at this point we have to update the map..
        sheetUpdateMap("Assignments", syncPayments.assign);
        sheetUpdateMap("Payments", syncPayments.paym);
    
        Logger.log("Total to do is %d", syncPayments.paym.length);
     
    
     
    }